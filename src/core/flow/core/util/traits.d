module flow.core.util.traits;

/// Returns: full qualified name of type
template fqn(T) {
    private import std.traits : fullyQualifiedName;

    enum fqn = fullyQualifiedName!T;
}

/** enables ducktyping casts
 * Examples:
 * class A {}; class B : A {}; auto foo = (new B()).as!A;
 */
T as(T, S)(S sym){return cast(T)sym;}