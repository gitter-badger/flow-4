module flow.core.data.data;

private import flow.core.data.engine;

class LockData : Data { mixin _data;
    private import core.sync.rwmutex : ReadWriteMutex;

    protected ReadWriteMutex lock;
    ReadWriteMutex.Reader reader() {return this.lock.reader;}
    ReadWriteMutex.Writer writer() {return this.lock.writer;}

    this() {
        this.lock = new ReadWriteMutex();
    }
}

/// identifyable data
class IdData : Data { mixin _data;
    private import std.uuid : UUID;

    @field UUID id;
}