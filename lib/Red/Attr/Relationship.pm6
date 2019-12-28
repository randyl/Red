use Red::AST::Infixes;
use Red::AST::Value;
use Red::HiddenFromSQLCommenting;
use X::Red::Exceptions;

unit role Red::Attr::Relationship[&rel1, &rel2?, Str :$model, Str :$require = $model, Bool :$optional];
has Mu:U $!type;

has Bool $.has-lazy-relationship = ?$model;

has Mu:U $!relationship-model;

has Bool $!loaded-model = False;

has Bool $!optional = $optional;

method transfer(Mu:U $package) {
    my $attr = Attribute.new: :$package, :$.name, :$.type;
    $attr but Red::Attr::Relationship[&rel1, &rel2, :$model, :$require]
}

method rel {
    rel1 self.package
}

method relationship-model(--> Mu:U)  is hidden-from-sql-commenting {
    if $model.defined && !$!loaded-model {
        my $t = ::($model);
        if !$t && $t ~~ Failure {
            require ::($require);
            $t = ::($model);
        }
        $!relationship-model = $t;
        $!loaded-model = True;
    }
    $!relationship-model;
}

method set-data(\instance, Mu $value) is hidden-from-sql-commenting {
    do given $.rel {
        my $attr = .attr;
        my $ref  = .ref;
        $attr.set_value: instance, $ref.attr.get_value: $value;
        instance.^set-dirty: $attr;
    }
}

method build-relationship(\instance) is hidden-from-sql-commenting {
    my \type = self.type;
    my \attr = self;
    my \rel-model = $model ?? self.relationship-model !! type ~~ Positional ?? type.of !! type;
    use nqp;
    nqp::bindattr(nqp::decont(instance), $.package, $.name, Proxy.new:
        FETCH => method () {
            do if type ~~ Positional {
                rel-model.^rs.where: rel1(rel-model).map(-> $rel {
                    X::Red::RelationshipNotColumn.new(:relationship(attr), :points-to($rel)).throw unless $rel ~~ Red::Column;
                    my $ref = $rel.ref;
                    X::Red::RelationshipNotRelated.new(:relationship(attr), :points-to($rel)).throw without $ref;
                    my $val = do given $ref.attr but role :: {
                        method package {
                            instance.WHAT
                        }
                    } {
                        instance.^get-attr: .name.substr: 2
                    }
                    my \value = ast-value $val;
                    Red::AST::Eq.new: $rel, value, :bind-right
                }).reduce: -> $left, $right {
                    Red::AST::AND.new: $left, $right
                }
            } else {
                my @models = rel1(instance.WHAT).map(-> $rel {
                    my $val = $rel.attr.get_value: instance;
                    do with $val {
                        my \value = ast-value $val;
                        Red::AST::Eq.new: $rel.ref, value, :bind-right
                    }
                }).grep(*.defined);
                return rel-model unless @models;
                rel-model.^rs.where(@models.reduce(-> $left, $right {
                    Red::AST::AND.new: $left, $right
                })).head
            }
        },
        STORE => method ($value where type) {
            die X::Assignment::RO.new(value => attr.type) unless attr.rw;
            if type !~~ Positional {
                attr.set-data: instance, $value
            } else {
                die "NYI Couldnt set value"
            }
        }
    );
    return
}

method relationship-type {
    do if self.type ~~ Positional {
        $model ?? self.relationship-model !! self.type.of
    } else {
        self.package
    }
}

method relationship-ast($type = Nil) is hidden-from-sql-commenting {
    my \type = self.relationship-type;
    my $col1 = rel1 type;
    my $col2 = $col1.ref($type);
    Red::AST::Eq.new: $col1, $col2
}

method join-type {
    with $!optional {
        return $!optional
                ?? :left
                !! :inner
    }
    do given rel1 self.relationship-type {
        when .nullable {
            :left
        }
        default {
            :inner
        }
    }
}