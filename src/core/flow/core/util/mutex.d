module flow.core.util.mutex;

private import core.sync.rwmutex;

class ContextMutex(CT) : ReadWriteMutex {
    private ReadWriteMutex[CT] locks;

    this() {super();}

    void add(CT ctx) {
        synchronized(this.writer)
            if(ctx !in this.locks)
                this.locks[ctx] = new ReadWriteMutex;
    }

    void remove(CT ctx) {
        synchronized(this.writer)
            if(ctx in this.locks)
                // we remove it as soon as noone uses it
                synchronized(this.locks[ctx].writer)
                    this.locks.remove(ctx);
    }

    ReadWriteMutex get(CT ctx) {
        this.add(ctx);

        synchronized(this.reader)
            if(ctx in this.locks)
                return this.locks[ctx];
        return null;
    }

    void clear() {
        synchronized(this.writer)
            foreach(c; this.locks.keys.dup) {
                auto m = this.locks[c];
                synchronized(m.writer)
                    this.locks.remove(c);
            }
    }
}