/** MADE UPGRADEABLE FOR FLOW, USE ONLY FOR RECYCLING THREADS */

/*          Copyright Sean Kelly 2005 - 2009.
 * Distributed under the Boost Software License, Version 1.0.
 *    (See accompanying file LICENSE or copy at
 *          http://www.boost.org/LICENSE_1_0.txt)
 */
module flow.core.data.mutex;

public import core.sync.exception;
private import core.sync.condition;
private import core.sync.mutex;
private import core.memory;
//private import core.thread;
version(unittest) private static import test = flow.core.util.test;

version( Posix )
{
    private import core.sys.posix.pthread;
}

struct RecursiveLocker {
    void delegate() readerLock;
    void delegate() writerLock;
    void delegate() readerUnlock;
    void delegate() writerUnlock;
}


////////////////////////////////////////////////////////////////////////////////
// DataMutex
//
// Reader reader();
// Writer writer();
////////////////////////////////////////////////////////////////////////////////


/**
 * This class represents a mutex that allows any number of readers to enter,
 * but when a writer enters, all other readers and writers are blocked.
 *
 * Please note that this mutex is not recursive and is intended to guard access
 * to data only.  Also, no deadlock checking is in place because doing so would
 * require dynamic memory allocation, which would reduce performance by an
 * unacceptable amount.  As a result, any attempt to recursively acquire this
 * mutex may well deadlock the caller, particularly if a write lock is acquired
 * while holding a read lock, or vice-versa.  In practice, this should not be
 * an issue however, because it is uncommon to call deeply into unknown code
 * while holding a lock that simply protects data.
 */
class DataMutex
{
    /**
     * Defines the policy used by this mutex.  Currently, two policies are
     * defined.
     *
     * The first will queue writers until no readers hold the mutex, then
     * pass the writers through one at a time.  If a reader acquires the mutex
     * while there are still writers queued, the reader will take precedence.
     *
     * The second will queue readers if there are any writers queued.  Writers
     * are passed through one at a time, and once there are no writers present,
     * all queued readers will be alerted.
     *
     * Future policies may offer a more even balance between reader and writer
     * precedence.
     */
    enum Policy
    {
        PREFER_READERS, /// Readers get preference.  This may starve writers.
        PREFER_WRITERS  /// Writers get preference.  This may starve readers.
    }


    ////////////////////////////////////////////////////////////////////////////
    // Initialization
    ////////////////////////////////////////////////////////////////////////////


    /**
     * Initializes a read/write mutex object with the supplied policy.
     *
     * Params:
     *  policy = The policy to use.
     *
     * Throws:
     *  SyncError on error.
     */
    this(RecursiveLocker rl, Policy policy = Policy.PREFER_WRITERS)
    {
        m_commonMutex = new Mutex;
        if( !m_commonMutex )
            throw new SyncError( "Unable to initialize mutex" );

        m_readerQueue = new Condition( m_commonMutex );
        if( !m_readerQueue )
            throw new SyncError( "Unable to initialize mutex" );

        m_writerQueue = new Condition( m_commonMutex );
        if( !m_writerQueue )
            throw new SyncError( "Unable to initialize mutex" );

        m_policy = policy;
        m_reader = new Reader(rl);
        m_writer = new Writer(rl);
    }

    ////////////////////////////////////////////////////////////////////////////
    // General Properties
    ////////////////////////////////////////////////////////////////////////////


    /**
     * Gets the policy used by this mutex.
     *
     * Returns:
     *  The policy used by this mutex.
     */
    @property Policy policy()
    {
        return m_policy;
    }


    ////////////////////////////////////////////////////////////////////////////
    // Reader/Writer Handles
    ////////////////////////////////////////////////////////////////////////////


    /**
     * Gets an object representing the reader lock for the associated mutex.
     *
     * Returns:
     *  A reader sub-mutex.
     */
    @property Reader reader()
    {
        return m_reader;
    }


    /**
     * Gets an object representing the writer lock for the associated mutex.
     *
     * Returns:
     *  A writer sub-mutex.
     */
    @property Writer writer()
    {
        return m_writer;
    }


    ////////////////////////////////////////////////////////////////////////////
    // Reader
    ////////////////////////////////////////////////////////////////////////////


    /**
     * This class can be considered a mutex in its own right, and is used to
     * negotiate a read lock for the enclosing mutex.
     */
    class Reader :
        Object.Monitor
    {
        /**
         * Initializes a read/write mutex reader proxy object.
         */
        this(RecursiveLocker rl)
        {
            //m_rl = rl;
            m_proxy.link = this;
            this.__monitor = &m_proxy;
        }


        /**
         * Acquires a read lock on the enclosing mutex.
         */
        @trusted void lock()
        {
            synchronized( m_commonMutex )
            {
                ++m_numQueuedReaders;
                scope(exit) --m_numQueuedReaders;

                while( shouldQueueReader )
                    m_readerQueue.wait();
				addActiveReader();

                //m_rl.readerLock();
            }
        }


        /**
         * Releases a read lock on the enclosing mutex.
         */
        @trusted void unlock()
        {
            synchronized( m_commonMutex )
            {
                //m_rl.readerUnlock();

                if( removeActiveReader() < 1 )
                {
                    if( m_numQueuedWriters > 0 )
                        m_writerQueue.notify();
                }
            }
        }

        /**
         * Attempts to acquire a read lock on the enclosing mutex.  If one can
         * be obtained without blocking, the lock is acquired and true is
         * returned.  If not, the lock is not acquired and false is returned.
         *
         * Returns:
         *  true if the lock was acquired and false if not.
         */
        bool tryLock()
        {
            assert(false, "child locking is not supporting tryLock");
        }


    private:
        //RecursiveLocker m_rl;

        @property bool shouldQueueReader()
        {
            if( m_numActiveWriters > 0 )
                return true;

            switch( m_policy )
            {
            case Policy.PREFER_WRITERS:
                 return m_numQueuedWriters > 0;

            case Policy.PREFER_READERS:
            default:
                 break;
            }

        return false;
        }

        struct MonitorProxy
        {
            Object.Monitor link;
        }

        MonitorProxy    m_proxy;
    }


    ////////////////////////////////////////////////////////////////////////////
    // Writer
    ////////////////////////////////////////////////////////////////////////////


    /**
     * This class can be considered a mutex in its own right, and is used to
     * negotiate a write lock for the enclosing mutex.
     */
    class Writer :
        Object.Monitor
    {
        /**
         * Initializes a read/write mutex writer proxy object.
         */
        this(RecursiveLocker rl)
        {
            //m_rl = rl;
            m_proxy.link = this;
            this.__monitor = &m_proxy;
        }


        /**
         * Acquires a write lock on the enclosing mutex.
         */
        @trusted void lock()
        {
            synchronized( m_commonMutex )
            {
                ++m_numQueuedWriters;
                scope(exit) --m_numQueuedWriters;

                while( shouldQueueWriter )
                    m_writerQueue.wait();
                ++m_numActiveWriters;

                //m_rl.readerLock();
            }
        }


        /**
         * Releases a write lock on the enclosing mutex.
         */
        @trusted void unlock()
        {
            synchronized( m_commonMutex )
            {
                //m_rl.readerUnlock();

                if( --m_numActiveWriters < 1 )
                {
                    switch( m_policy )
                    {
                    default:
                    case Policy.PREFER_READERS:
                        if( m_numQueuedReaders > 0 )
                            m_readerQueue.notifyAll();
                        else if( m_numQueuedWriters > 0 )
                            m_writerQueue.notify();
                        break;
                    case Policy.PREFER_WRITERS:
                        if( m_numQueuedWriters > 0 )
                            m_writerQueue.notify();
                        else if( m_numQueuedReaders > 0 )
                            m_readerQueue.notifyAll();
                    }
                }
            }
        }


        /**
         * Attempts to acquire a write lock on the enclosing mutex.  If one can
         * be obtained without blocking, the lock is acquired and true is
         * returned.  If not, the lock is not acquired and false is returned.
         *
         * Returns:
         *  true if the lock was acquired and false if not.
         */
        bool tryLock()
        {
            assert(false, "child locking is not supporting tryLock");
        }


    private:
        //RecursiveLocker m_rl;

        @property bool shouldQueueWriter()
        {
            if( m_numActiveWriters > 0 ||
                m_numActiveReaders > 0 )
                return true;
            switch( m_policy )
            {
            case Policy.PREFER_READERS:
                return m_numQueuedReaders > 0;

            case Policy.PREFER_WRITERS:
            default:
                 break;
            }

        return false;
        }

        struct MonitorProxy
        {
            Object.Monitor link;
        }

        MonitorProxy    m_proxy;
    }


private:
    Policy      m_policy;
    Reader      m_reader;
    Writer      m_writer;

    Mutex       m_commonMutex;
    Condition   m_readerQueue;
    Condition   m_writerQueue;

    int         m_numQueuedReaders;
	int         m_numActiveReaders;
    int         m_numQueuedWriters;
    int         m_numActiveWriters;

	void addActiveReader() {
		++m_numActiveReaders;
	}

	int removeActiveReader() {
		auto left = --m_numActiveReaders;
		
		return left;
	}
}