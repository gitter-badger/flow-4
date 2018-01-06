module flow.core.util.ops;

private import flow.core.util.traits;
private import flow.core.util.proc;

final class Operator {
    private import core.atomic : atomicOp, atomicLoad, MemoryOrder;
    private import core.sync.condition : Condition;
    private import core.thread : Thread, Duration, msecs;
    
    private shared size_t _count; // counting async operations

    @property count() {return atomicLoad!(MemoryOrder.raw)(this._count);}
    @property empty() {return atomicOp!"=="(this._count, 0.as!size_t);}

    void release() {
        atomicOp!"-="(this._count, 1.as!size_t);
    }

    void async(Processor proc, void delegate() f, long time = long.init) {
        this.async(proc, f, (Throwable thr){}, time);
    }

    void async(Processor proc, void delegate() f, void delegate(Throwable) e, long time = long.init) {
        import std.stdio : writeln;
        import std.parallelism : taskPool, task;
        
        atomicOp!"+="(this._count, 1.as!size_t);
        auto job = new Job({
            f();
            this.release();
        }, (Throwable thr){
            scope(exit)
                this.release();
            e(thr);
        }, time);
        proc.run(job);
    }

    void join(Duration interval = 5.msecs) {
        while(atomicOp!"!="(this._count, 0.as!size_t))
            Thread.sleep(interval);
    }
}