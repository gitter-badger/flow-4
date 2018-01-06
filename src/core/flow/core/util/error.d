module flow.core.util.error;

/// mixin allowing to derrive from FlowError
mixin template error() {
    private import flow.core.util.traits : fqn;

    override @property string type() {return fqn!(typeof(this));}

    this(string msg = string.init) {
        super(msg != string.init ? msg : this.type);
    }
}

/// mixin allowing to derrive from FlowException
mixin template exception() {
    private import flow.core.data.base : Data;
    private import flow.core.util.traits : fqn;

    override @property string type() {return fqn!(typeof(this));}

    this(string msg = string.init, Data d = null, Exception[] i = null) {
        super(msg != string.init ? msg : this.type, d, i);
    }
}

/// smart error knowing its type
class FlowError : Error {
    /// type name
	abstract @property string type();

    /// ctor
    this(string msg) {super(msg);}
}

/// smart exception knowing its type and storing context data
class FlowException : Exception {
    private import flow.core.data.base : Data;

    /// type name
	abstract @property string type();

    /// context data
    Data data;

    // inner exceptions
    Exception[] inner;

    /// ctor
    this(string msg = string.init, Data d = null, Exception[] i = null) {
        super(msg);
        
        this.data = d;
        this.inner = i;
    }
}

/// thrown when hitting code which is not implemented yet
class NotImplementedError : FlowError {mixin error;}