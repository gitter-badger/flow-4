module flow.core.crypt;

private import deimos.openssl.ssl;
private import flow.core.util.error;
private import flow.core.util;

class CryptoInitException : FlowException {mixin exception;}

class CryptoException : FlowException {mixin exception;}

private RSA* load(T)(string key) if(is(T==RSA)) {
    import std.conv : to;

    if(key !is null) {
        BIO* bio = BIO_new_mem_buf(key.ptr.as!(void*), key.length.to!int);
        BIO_set_flags(bio, BIO_FLAGS_BASE64_NO_NL);
        scope(exit) BIO_free(bio);
        
        return PEM_read_bio_RSAPrivateKey(bio, null, null, null);
    }

    return null;
}

private struct RsaPrivCtx {
    RSA* rsa;
}

private RsaPrivCtx createRsaPrivCtx(string key) {
    auto ctx = RsaPrivCtx();
    ctx.rsa = key.load!(RSA);
    return ctx;
}

private void free(RsaPrivCtx ctx) {
    RSA_free(ctx.rsa);
}

private ubyte[] hashMd5(ref ubyte[] data) {
    import deimos.openssl.md5;

    auto digest = MD5(data.ptr, data.length, null);
    return digest[0..MD5_DIGEST_LENGTH];
}

private ubyte[] hashSha1(ref ubyte[] data) {
    import deimos.openssl.sha;

    auto digest = SHA1(data.ptr, data.length, null);
    return digest[0..SHA_DIGEST_LENGTH];
}

private ubyte[] hashSha256(ref ubyte[] data) {
    import deimos.openssl.sha;

    auto digest = SHA256(data.ptr, data.length, null);
    return digest[0..SHA256_DIGEST_LENGTH];
}

private ubyte[] sign(ref ubyte[] data, RSA* key, string hash) {
    switch(hash) {
        case SSL_TXT_MD5:
            return data.sign!(
                SSL_TXT_MD5, NID_hmacWithMD5, "hashMd5"
            )(key);
        case SSL_TXT_SHA:
            return data.sign!(
                SSL_TXT_SHA, NID_hmacWithSHA1, "hashSha1"
            )(key);
        case SSL_TXT_SHA256:
            return data.sign!(
                SSL_TXT_SHA256, NID_hmacWithSHA256, "hashSha256"
            )(key);
        default: assert(false);
    }
}

private ubyte[] sign(string title, int hash, string hashFunc)(ref ubyte[] data, RSA* key) {
    import deimos.openssl.err : ERR_error_string, ERR_get_error;
    import flow.core.data : bin;
    import std.conv : to;

    auto bs = RSA_size(key);
    auto hdata = mixin(hashFunc)(data);
    auto ds = hdata.length.to!uint;
    uint ss;

    auto buf = new ubyte[bs];
    if(RSA_sign(hash, hdata.ptr, ds, buf.ptr, &ss, key) != 1 || ss < 1)
        throw new CryptoException("rsa signing error ["~title~"]: "~ERR_error_string(ERR_get_error(), null).to!string);
    
    buf.length = ss;
    return hash.bin~buf;
}

private bool verify(ref ubyte[] data, ref ubyte[] s, RSA* key) {
    import flow.core.data : unbin;
    auto hash = s[0..int.sizeof].unbin!int;
    auto sig = s[int.sizeof..$];

    switch(hash) {
        case NID_hmacWithMD5:
            return data.verify!(NID_hmacWithMD5, "hashMd5")(sig, key);
        case NID_hmacWithSHA1:
            return data.verify!(NID_hmacWithSHA1, "hashSha1")(sig, key);
        case NID_hmacWithSHA256:
            return data.verify!(NID_hmacWithSHA256, "hashSha256")(sig, key);
        default: return false;
    }
}

private bool verify(int hash, string hashFunc)(ref ubyte[] data, ref ubyte[] sig, RSA* key) {
    import deimos.openssl.err : ERR_error_string, ERR_get_error;
    import flow.core.data : unbin;
    import std.conv : to;

    auto hdata = mixin(hashFunc)(data);
    auto ds = hdata.length.to!uint;
    return RSA_verify(hash, hdata.ptr, ds, sig.ptr, sig.length.to!uint, key) == 1;
}

private ubyte[] encryptRsa(ref ubyte[] data, RSA* key) {
    import deimos.openssl.err : ERR_error_string, ERR_get_error;
    import std.conv : to;

    auto bs = RSA_size(key);
    auto ds = data.length;

    ubyte[] crypt;
    auto buffer = new ubyte[bs];
    int ret;
    size_t i = 0;
    while(i < ds) {
        auto end = (i+bs)-RSA_PKCS1_PADDING_SIZE < ds ? (i+bs)-RSA_PKCS1_PADDING_SIZE : ds;

        auto len = (end-i).to!int;
        auto from = data[i..end];

        ret = RSA_public_encrypt(len, from.ptr, buffer.ptr, key, RSA_PKCS1_PADDING);
        if(ret == -1)
            throw new CryptoException("rsa encryption error: "~ERR_error_string(ERR_get_error(), null).to!string);

        i = end;
        crypt ~= buffer[0..ret];
    }

    return crypt;
}

private ubyte[] decryptRsa(ref ubyte[] crypt, RSA* key) {
    import deimos.openssl.err : ERR_error_string, ERR_get_error;
    import std.conv : to;

    auto bs = RSA_size(key);
    auto ds = crypt.length;

    ubyte[] data;
    auto buffer = new ubyte[bs-RSA_PKCS1_PADDING_SIZE];
    int ret;
    size_t i = 0;
    while(i < ds) {
        auto end = i+bs < ds ? i+bs : ds;

        auto len = (end-i).to!int;
        auto from = crypt[i..end];
        
        ret = RSA_private_decrypt(len, from.ptr, buffer.ptr, key, RSA_PKCS1_PADDING);
        if(ret == -1)
            return null;

        i = end;
        data ~= buffer[0..ret]; // trim data to real size
    }

    return data;
}

private X509* load(T)(string crt) if(is(T==X509)) {
    import std.conv : to;

    // for security reasons certificate first
    if(crt !is null) {
        BIO* bio = BIO_new_mem_buf(crt.ptr.as!(void*), crt.length.to!int);
        BIO_set_flags(bio, BIO_FLAGS_BASE64_NO_NL);
        scope(exit) BIO_free(bio);

        return PEM_read_bio_X509(bio, null, null, null);
    }

    return null;
}

private struct GenCipher {
    ubyte[] key, iv, data;
}

private GenCipher loadCipher(ubyte[] data) {
    import flow.core.data.bin : unpack;

    auto key = data.unpack;
    auto iv = data.unpack;

    GenCipher gen;
    gen.key = key;
    gen.iv = iv;
    return gen;
}

/** cipher and hash decides what generator
will run for creating it it */
private GenCipher genCipher(string cipher, string hash) {
    switch(cipher~hash) {
        case SSL_TXT_AES128~SSL_TXT_MD5:
            return genCipher!(SSL_TXT_AES128~"+"~SSL_TXT_MD5, "EVP_aes_128_cbc", "EVP_md5", 16)();
        case SSL_TXT_AES256~SSL_TXT_MD5:
            return genCipher!(SSL_TXT_AES256~"+"~SSL_TXT_MD5, "EVP_aes_256_cbc", "EVP_md5", 32)();
        case SSL_TXT_AES128~SSL_TXT_SHA:
            return genCipher!(SSL_TXT_AES128~"+"~SSL_TXT_SHA, "EVP_aes_128_cbc", "EVP_sha1", 16)();
        case SSL_TXT_AES256~SSL_TXT_SHA:
            return genCipher!(SSL_TXT_AES256~"+"~SSL_TXT_SHA, "EVP_aes_256_cbc", "EVP_sha1", 32)();
        case SSL_TXT_AES128~SSL_TXT_SHA256:
            return genCipher!(SSL_TXT_AES128~"+"~SSL_TXT_SHA256, "EVP_aes_128_cbc", "EVP_sha256", 16)();
        case SSL_TXT_AES256~SSL_TXT_SHA256:
            return genCipher!(SSL_TXT_AES256~"+"~SSL_TXT_SHA256, "EVP_aes_256_cbc", "EVP_sha256", 32)();
        default: assert(false);
    }
}

/// openssl cipher generator
private GenCipher genCipher(string title, string cipherFunc, string hashFunc, size_t length)() {
    import deimos.openssl.rand : RAND_bytes;
    import flow.core.data.bin : pack;

    immutable ks = length;
    immutable rounds = 3;

    auto pass = new ubyte[ks]; RAND_bytes(pass.ptr, ks);

    auto key = new ubyte[ks];
    auto iv = new ubyte[ks];
    
    auto ret = EVP_BytesToKey(mixin(cipherFunc)(), mixin(hashFunc)(), null, pass.ptr, ks, rounds, key.ptr, iv.ptr);

    if(ret != ks)
        new CryptoException("couldn't generate "~title~" cipher");

    // they are packed together for communicating cipher
    auto data = key.pack~iv.pack;

    GenCipher ciph;
    ciph.key = key;
    ciph.iv = iv;
    ciph.data = data;

    return ciph;
}

private ubyte[] encrypt(ref ubyte[] data, string cipher, GenCipher ciph) {
    switch(cipher) {
        case SSL_TXT_AES128:
            return data.encrypt!(
                SSL_TXT_AES128~"+"~SSL_TXT_SHA, "EVP_aes_128_cbc"
            )(ciph);
        case SSL_TXT_AES256:
            return data.encrypt!(
                SSL_TXT_AES256~"+"~SSL_TXT_SHA, "EVP_aes_256_cbc"
            )(ciph);
        default: assert(false);
    }
}

/// openssl cipher context generator
private ubyte[] encrypt(string title, string cipherFunc)(ref ubyte[] data, GenCipher ciph) {
    import deimos.openssl.aes;
    import deimos.openssl.err : ERR_error_string, ERR_get_error;
    import std.conv : to;

    EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new;
    scope(exit) EVP_CIPHER_CTX_free(ctx);
    
    //EVP_CIPHER_CTX_init(&ctx);
    //scope(exit) EVP_CIPHER_CTX_cleanup(&ctx);
    if(!EVP_EncryptInit_ex(ctx, mixin(cipherFunc)(), null, ciph.key.ptr, ciph.iv.ptr))
        new CryptoException("couldn't initialize "~title~" encryption context");

    // double check
    if(!EVP_EncryptInit_ex(ctx, null, null, null, null))
        new CryptoException("couldn't initialize "~title~" encryption context");

    auto buf = new ubyte[data.length+AES_BLOCK_SIZE];
    auto ds = data.length.to!int;
    int bs, fs;

    if(!EVP_EncryptUpdate(ctx, buf.ptr, &bs, data.ptr, ds))
        throw new CryptoException("cipher encryption error: "~ERR_error_string(ERR_get_error(), null).to!string);
    
    if(!EVP_EncryptFinal_ex(ctx, buf.ptr+bs, &fs))
        throw new CryptoException("cipher encryption error: "~ERR_error_string(ERR_get_error(), null).to!string);

    buf.length = bs+fs;
    return buf;
}

private ubyte[] decrypt(ref ubyte[] crypt, string cipher, GenCipher ciph) {
    switch(cipher) {
        case SSL_TXT_AES128:
            return crypt.decrypt!(
                SSL_TXT_AES128~"+"~SSL_TXT_SHA, "EVP_aes_128_cbc"
            )(ciph);
        case SSL_TXT_AES256:
            return crypt.decrypt!(
                SSL_TXT_AES256~"+"~SSL_TXT_SHA, "EVP_aes_256_cbc"
            )(ciph);
        default: assert(false);
    }
}

/// openssl cipher context generator
private ubyte[] decrypt(string title, string cipherFunc)(ref ubyte[] crypt, GenCipher ciph) {
    import deimos.openssl.aes;
    import deimos.openssl.err : ERR_error_string, ERR_get_error;
    import std.conv : to;

    EVP_CIPHER_CTX* ctx = EVP_CIPHER_CTX_new;
    scope(exit) EVP_CIPHER_CTX_free(ctx);
    
    //EVP_CIPHER_CTX_init(&ctx);
    //scope(exit) EVP_CIPHER_CTX_cleanup(&ctx);
    if(!EVP_DecryptInit_ex(ctx, mixin(cipherFunc)(), null, ciph.key.ptr, ciph.iv.ptr))
        new CryptoException("couldn't initialize "~title~" decryption context");

    // double check
    if(!EVP_DecryptInit_ex(ctx, null, null, null, null))
        new CryptoException("couldn't initialize "~title~" encryption context");

    auto buf = new ubyte[crypt.length];            
    auto ds = crypt.length.to!int;
    int bs, fs;

    if(!EVP_DecryptUpdate(ctx, buf.ptr, &bs, crypt.ptr, ds))
        throw new CryptoException("cipher decryption error: "~ERR_error_string(ERR_get_error(), null).to!string);

    if(!EVP_DecryptFinal_ex(ctx, buf.ptr+bs, &fs))
        throw new CryptoException("cipher decryption error: "~ERR_error_string(ERR_get_error(), null).to!string);

    buf.length = bs+fs;
    return buf;
}

/** it has to get locked so no thread can
kill others ctx by destructing it however
multiple readers can use it concurrently */
private class Cipher {
    private import core.sync.rwmutex : ReadWriteMutex;
    private import core.thread;
    private import std.datetime.systime;

    private ReadWriteMutex lock;

    /// a cipher algorithm needs a hash algorithm
    private string cipher, hash;

    /// generated cipher
    private GenCipher gen;

    // lazy loading
    private void ensureGen() {
        if(this.gen.data is null)
            this.gen = genCipher(cipher, hash);
    }

    /// merged cipher data
    @property ubyte[] data() {
        synchronized(this.lock.writer) {
            this.ensureGen();
            return this.gen.data;
        }
    }

    this(string cipher, string hash) {
        this.lock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);

        this.cipher = cipher;
        this.hash = hash;
    }

    this(string cipher, string hash, ref ubyte[] data) {
        this.gen = loadCipher(data);

        this(cipher, hash);
    }

    void dispose() {
        this.destroy;
    }

    ubyte[] encrypt(ref ubyte[] data) {
        import flow.core.util.log : Log, LL;
        import std.conv : to;

        synchronized(this.lock.reader) try {
            return data.encrypt(this.cipher, this.gen);
        } catch(Exception exc) {
            Log.msg(LL.Error, "decrypting by cipher failed", exc);
        }

        return null;
    }

    ubyte[] decrypt(ref ubyte[] crypt) {
        import flow.core.util.log : Log, LL;
        import std.conv : to;

        synchronized(this.lock.reader) try {
            return crypt.decrypt(this.cipher, this.gen);
        } catch(Exception exc) {
            Log.msg(LL.Error, "decrypting by cipher failed", exc);
        }

        return null;
    }
}

// @property bool valid() { return ; }

private struct RsaPubCtx {
    X509* crt;
    EVP_PKEY* pub;
    RSA* rsa;
    size_t bs; // block size of rsa key
}

private RsaPubCtx createRsaPubCtx(string crt) {
    auto ctx = RsaPubCtx();
    ctx.crt = crt.load!(X509);
    ctx.pub = X509_get_pubkey(ctx.crt);
    ctx.rsa = EVP_PKEY_get1_RSA(ctx.pub);
    ctx.bs = RSA_size(ctx.rsa);
    return ctx;
}

private void free(RsaPubCtx ctx) {
    RSA_free(ctx.rsa);
    EVP_PKEY_free(ctx.pub);
    X509_free(ctx.crt);  
}

private class Peer {
    private import core.sync.rwmutex : ReadWriteMutex;
    private import core.thread;
    private import std.datetime.systime;

    private ReadWriteMutex lock;

    private Crypto crypto;

    private string _crt;

    private RsaPubCtx[Thread] _ctx;
    private @property RsaPubCtx ctx() {return this._ctx[Thread.getThis];}

    /// lazy and per thread loading
    private void ensureCtx() {
        /* as Cipher.ctx */
        if(Thread.getThis !in this._ctx) {
            RsaPubCtx ctx;
            try {
                ctx = this._crt.createRsaPubCtx;
            } catch(Exception exc) {
                throw new CryptoException("couldn't load peers certificate", null, [exc]);
            }

            if(ctx.crt is null || ctx.pub == null || ctx.rsa is null && ctx.bs > 0)
                throw new CryptoException("couldn't load peers certificate");
            
            this._ctx[Thread.getThis] = ctx;
        }
    }

    private Duration validity;

    /// ciphers used to encrypt outgoing packages
    private Cipher outgoing;
    private ubyte[] outCrypt;
    private SysTime outValidity;

    private void createOutgoing() {
        import flow.core.data.bin : bin, pack;

        Cipher ciph = new Cipher(this.crypto.cipher, this.crypto.hash);
        
        // encrypts and signs generated cipher
        auto data = ciph.data;
        this.ensureCtx();
        auto crypt = data.encryptRsa(this.ctx.rsa);
        auto sig = crypt.sign(this.crypto.ctx.rsa, this.crypto.hash);
        auto cipherBin = ciph.cipher.bin;
        auto hashBin = ciph.hash.bin;
        this.outCrypt = cipherBin.pack~hashBin.pack~sig.pack~crypt.pack;
        this.outValidity = Clock.currTime + this.validity;
        this.outgoing = ciph;
    }

    private @property void ensureOutgoing() {
        import core.memory : GC;
        synchronized(this.lock.writer)  {
            if(this.outgoing is null || this.outValidity < Clock.currTime) {
                if(this.outgoing !is null)
                    this.outgoing.dispose(); GC.free(&this.outgoing);
                this.createOutgoing();
            }
        }
    }

    /// ciphers used to decrypt incoming packages
    private Cipher[ulong] incoming;
    private SysTime[ulong] inValidity;

    this(Crypto crypto, string crt, Duration outValidity, bool check = true) {
        this.lock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);

        this.crypto = crypto;
        this._crt = crt;
        this.validity = outValidity;

        if(check) {
            /* TODO check certificate against authorities
            and destination against cn of certificate*/
        }
    }

    void dispose() {
        synchronized(this.lock.writer)
            foreach(ctx; this._ctx.values)
                ctx.free;

        this.destroy;
    }

    bool check() {
        this.ensureCtx();

        synchronized(this.lock.reader) {
            return false; // TODO check with authority
        }
    }

    /// verifies sig of data using peers certificate
    bool verify(ref ubyte[] data, ref ubyte[] sig) {
        this.ensureCtx();

        synchronized(this.lock.reader) {
            return data.verify(sig, this.ctx.rsa);
        }
    }

    /// encrypts data via RSA for crt
    private ubyte[] encryptRsa(ref ubyte[] data) {
        this.ensureCtx();

        synchronized(this.lock.reader) {
            return data.encryptRsa(this.ctx.rsa);
        }
    }

    ubyte[] encrypt(ref ubyte[] data) {
        import flow.core.data.bin : pack;
        // binary rule: crypted cipher is packed, rest is data
        this.ensureCtx();
        this.ensureOutgoing();
        
        synchronized(this.lock.reader) {
            auto crypt = this.outgoing.encrypt(data);
            return this.outCrypt.pack~crypt;
        }
    }

    /// wipes unused incoming ciphers
    private void cleanInCiphers() {
        import core.memory : GC;
        foreach(h, c; this.incoming)
            if(this.inValidity[h] < Clock.currTime) {
                this.incoming.remove(h);
                c.dispose(); GC.free(&c);
            }
    }

    /// unpacks received cipher data and creates its stuff if needed
    private Cipher addInCipher(ref ubyte[] cc) {
        import flow.core.data.bin : unpack, unbin;
        import std.conv : to;

        if(cc !is null) {
            auto cipher = cc.unpack.unbin!string;
            auto hash = cc.unpack.unbin!string;
            // get signature out of crypted cipher
            auto sig = cc.unpack;

            /* generate cipher id out of crypted data
            due to rsa encryption of randoms this should be representative */
            auto id = sig[0..ulong.sizeof].unbin!long;

            synchronized(this.lock.writer) {        
                // if cipher id is known stay in reader mode and return cipher
                if(id in this.incoming)
                    return this.incoming[id];
                // otherwise switch to writer mode and create
                else {
                    // clean what is expired (requires writer mode)
                    this.cleanInCiphers();

                    // get crypted data out of crypted cipher
                    auto crypt = cc.unpack;

                    auto sigOk = sig !is null && crypt.verify(sig, this.ctx.rsa);
                    auto data = crypt.decryptRsa(this.crypto.ctx.rsa);
                    if(data !is null) { // add it if it could get decrypted
                        auto ciph = new Cipher(cipher, hash, data);
                        this.inValidity[id] = Clock.currTime + this.validity;
                        
                        this.incoming[id] = ciph;

                        return ciph;
                    } else return null;
                }
            }
        } else return null;
    }

    /// decrypts encrypted data returning its plain bytes unless there is a key
    ubyte[] decrypt(ubyte[] crypt) { // parameter crypt will get modified (never ref)
        import flow.core.data.bin : unpack;
        import flow.core.util.log : Log, LL;
        try {
            // binary rule: crypted cipher is packed, rest is data
            auto cc = crypt.unpack;
            this.ensureCtx();
            auto ciph = this.addInCipher(cc);

            synchronized(this.lock.reader) {                
                if(ciph !is null)
                    return ciph.decrypt(crypt);
                else return crypt; // if there is no in cipher, it is assumed pkg is not encrypted;
            }
        } catch(Exception exc) {
            Log.msg(LL.Error, "decrypting by cipher failed", exc);
        }

        return null;
    }
}

private void loadSSL() {
    import deimos.openssl.conf;

    // initializing ssl
    ERR_load_CRYPTO_strings();
    //OpenSSL_add_all_algorithms();
    OPENSSL_config(null);
}

private void cleanSSL() {
    import deimos.openssl.err;

    //EVP_cleanup();
    //ERR_free_strings();
}

package final class Crypto {
    private import core.sync.rwmutex : ReadWriteMutex;
    private import core.thread;
    private import core.time;

    private ReadWriteMutex lock;

    private string addr;
    private string key;
    private string crt;

    private RsaPrivCtx[Thread] _ctx;
    private @property RsaPrivCtx ctx() {return this._ctx[Thread.getThis];}

    /// lazy and per thread loading
    private @property void ensureCtx() {
        RsaPrivCtx ctx;
        /* as Cipher.ctx */
        if(Thread.getThis !in this._ctx) {
            try {
                ctx = this.key.createRsaPrivCtx;
            } catch(Exception exc) {
                throw new CryptoException("couldn't load own rsa key", null, [exc]);
            }

            if(ctx.rsa is null)
                throw new CryptoException("couldn't load own rsa key");
            
            this._ctx[Thread.getThis] = ctx;
        }
    }

    // checking peers certivicate for CA validity?
    private bool _check;

    /// algorithms to use
    private string cipher, hash;

    /// validity time for outgoing cipher
    private Duration cipherValidity;

    /// available destinations
    private Peer[string] peers;

    private Peer get(string p) {
        if(p in this.peers)
            return this.peers[p];
        else throw new CryptoException("peer \""~p~"\" not found");
    }

    shared static bool initSSL;

    //https://www.youtube.com/watch?v=uwzWVG_LDGA

    this(string addr, string key, string crt, string cipher, string hash, bool check = true, Duration cipherValidity = 10.minutes) {
        this.lock = new ReadWriteMutex(ReadWriteMutex.Policy.PREFER_WRITERS);

        synchronized if(!initSSL)
            loadSSL();

        this.addr = addr;
        this.key = key;
        this.crt = crt;
        
        /* aes-256 in combination with sha256 is
        the default cipher and hash pair to use */
        this.cipher = cipher != string.init ? cipher : SSL_TXT_AES128;
        this.hash = hash != string.init ? hash : SSL_TXT_MD5;
        this._check = check;
        this.cipherValidity = cipherValidity;
    }

    void dispose() {
        synchronized(this.lock.writer)
            foreach(ctx; this._ctx.values)
                ctx.free;

        this.destroy;
    }

    /// add peer
    void add(string p, string crt) {
        synchronized(this.lock.writer)
            if(p !in this.peers)
                this.peers[p] = new Peer(this, crt, this.cipherValidity, this._check);
    }

    /// remove it again
    void remove(string p) {
        import core.memory : GC;
        synchronized(this.lock.writer)
            if(p in this.peers) {
                auto peer = this.peers[p];
                peer.dispose(); GC.free(&peer);
                this.peers.remove(p);
            }
    }

    /// NOTE: unsupported yet
    bool check(string dst) {
        synchronized(this.lock.reader)
            return this.get(dst).check();
    }

    /** signs data using private key
    returns signature if there is a key else null */
    ubyte[] sign(ref ubyte[] data) {
        this.ensureCtx();

        synchronized(this.lock.reader)
            return data.sign(this.ctx.rsa, this.hash);
    }

    bool verify(ref ubyte[] data, ref ubyte[] sig, string src) {
        synchronized(this.lock.reader)
            return this.get(src).verify(data, sig);
    }

    ubyte[] encryptRsa(ref ubyte[] data, string dst) {
        this.ensureCtx();

        synchronized(this.lock.reader)
            return this.get(dst).encryptRsa(data);
    }

    ubyte[] decryptRsa(ref ubyte[] crypt) {
        this.ensureCtx();

        synchronized(this.lock.reader)
            return crypt.decryptRsa(this.ctx.rsa);
    }

    ubyte[] encrypt(ref ubyte[] data, string dst) {
        this.ensureCtx();

        synchronized(this.lock.reader)
            return this.get(dst).encrypt(data);
    }

    ubyte[] decrypt(ref ubyte[] crypt, string src) {
        this.ensureCtx();
        
        synchronized(this.lock.reader)
            return this.get(src).decrypt(crypt);
    }
}

version(unittest) {
    class TestKeys {
        shared static string selfKey, selfCrt;
        shared static string signedKey, signedCrt;
        shared static string invalidKey, invalidCrt;
        shared static string revokedKey, revokedCrt;

        shared static this() {
            import std.file : readText, thisExePath;
            import std.path : buildPath, dirName;

            string base = thisExePath.dirName.buildPath("..", "util", "ssl");

            selfKey = base.buildPath("self.key").readText;
            selfCrt = base.buildPath("self.crt").readText;
            
            signedKey = base.buildPath("signed.key").readText;
            signedCrt = base.buildPath("signed.crt").readText;

            invalidKey = base.buildPath("invalid.key").readText;
            invalidCrt = base.buildPath("invalid.crt").readText;

            revokedKey = base.buildPath("revoked.key").readText;
            revokedCrt = base.buildPath("revoked.crt").readText;
        }

        @property static bool loaded() {
            return selfKey != string.init
                && selfCrt != string.init
                && signedKey != string.init
                && signedCrt != string.init
                && invalidKey != string.init
                && invalidCrt != string.init
                && revokedKey != string.init
                && revokedCrt != string.init;
        }
    }
}

unittest { test.header("crypt: rsa encrypt/decrypt");
    import core.exception : AssertError;
    import deimos.openssl.ssl;
    import flow.core.data : bin, unbin;

    assert(TestKeys.loaded, "keys were not loaded! did you execute util/ssl/gen.sh on a CA free host?");

    auto selfC = new Crypto("self", TestKeys.selfKey, TestKeys.selfCrt, SSL_TXT_AES128, SSL_TXT_MD5, false);
    auto signedC = new Crypto("signed", TestKeys.signedKey, TestKeys.signedCrt, SSL_TXT_AES128, SSL_TXT_MD5, false);
    auto invalidC = new Crypto("invalid", TestKeys.invalidKey, TestKeys.invalidCrt, SSL_TXT_AES128, SSL_TXT_MD5, false);
    selfC.add("signed", TestKeys.signedCrt);
    selfC.add("invalid", TestKeys.invalidCrt);
    signedC.add("self", TestKeys.selfCrt);
    signedC.add("invalid", TestKeys.invalidCrt);
    invalidC.add("signed", TestKeys.signedCrt);
    invalidC.add("self", TestKeys.selfCrt);

    auto orig = "CRYPTED MESSAGE: hello world, I'm coming".bin;
    
    auto crypt = signedC.encryptRsa(orig, "self");
    auto decrypt = selfC.decryptRsa(crypt);
    auto wrong = invalidC.decryptRsa(crypt);
    assert(orig == decrypt, "original message and decrypt of self crypto mismatch");
    assert(wrong is null, "wrong rsa crypt wasn't null");

    selfC.remove("signed");
    selfC.remove("invalid");
    signedC.remove("self");
    signedC.remove("invalid");
    invalidC.remove("signed");
    invalidC.remove("self");

    selfC.dispose();
    signedC.dispose();
    invalidC.dispose();
test.footer; }

unittest { test.header("crypt: rsa sign/verify");
    import deimos.openssl.ssl;
    import flow.core.data : bin, unbin;

    assert(TestKeys.loaded, "keys were not loaded! did you execute util/ssl/gen.sh on a CA free host?");

    auto selfC = new Crypto("self", TestKeys.selfKey, TestKeys.selfCrt, SSL_TXT_AES128, SSL_TXT_MD5, false);
    auto signedC = new Crypto("signed", TestKeys.signedKey, TestKeys.signedCrt, SSL_TXT_AES128, SSL_TXT_MD5, false);
    auto invalidC = new Crypto("invalid", TestKeys.invalidKey, TestKeys.invalidCrt, SSL_TXT_AES128, SSL_TXT_MD5, false);
    selfC.add("signed", TestKeys.signedCrt); selfC.add("invalid", TestKeys.invalidCrt);
    signedC.add("self", TestKeys.selfCrt); signedC.add("invalid", TestKeys.invalidCrt);
    invalidC.add("signed", TestKeys.signedCrt); invalidC.add("self", TestKeys.selfCrt);

    auto msg = "CRYPTED MESSAGE: hello world, I'm coming".bin;
    
    auto sign = signedC.sign(msg);
    assert(selfC.verify(msg, sign, "signed"), "correct sig was verified as wrong");
    assert(!selfC.verify(msg, sign, "invalid"), "wrong sig was verified as correct");
    assert(invalidC.verify(msg, sign, "signed"), "correct sig was verified as wrong");

    selfC.remove("signed");
    selfC.remove("invalid");
    signedC.remove("self");
    signedC.remove("invalid");
    invalidC.remove("signed");
    invalidC.remove("self");

    selfC.dispose();
    signedC.dispose();
    invalidC.dispose();
test.footer; }

version(unittest) {
    void runCipherTest(string cipher, string hash) { test.header("crypt: "~cipher~" using "~hash~" cipher encrypt/decrypt");
        import flow.core.data : bin, unbin;


        auto selfC = new Crypto("self", TestKeys.selfKey, TestKeys.selfCrt, cipher, hash, false);
        auto signedC = new Crypto("signed", TestKeys.signedKey, TestKeys.signedCrt, cipher, hash, false);
        auto invalidC = new Crypto("invalid", TestKeys.invalidKey, TestKeys.invalidCrt, cipher, hash, false);
        selfC.add("signed", TestKeys.signedCrt); selfC.add("invalid", TestKeys.invalidCrt);
        signedC.add("self", TestKeys.selfCrt); signedC.add("invalid", TestKeys.invalidCrt);
        invalidC.add("signed", TestKeys.signedCrt); invalidC.add("self", TestKeys.selfCrt);

        auto orig = "CRYPTED MESSAGE: hello world, I'm coming".bin;
        
        auto crypt = signedC.encrypt(orig, "self");
        auto decrypt = selfC.decrypt(crypt, "signed");
        auto wrong = invalidC.decrypt(crypt, "signed");
        assert(orig == decrypt, "original message and decrypt mismatch");
        assert(orig != wrong, "original message and wrong match");

        selfC.remove("signed");
        selfC.remove("invalid");
        signedC.remove("self");
        signedC.remove("invalid");
        invalidC.remove("signed");
        invalidC.remove("self");
    test.footer; }
}

unittest { test.header("crypt: cipher encrypt/decrypt");
    import deimos.openssl.ssl;

    assert(TestKeys.loaded, "keys were not loaded! did you execute util/ssl/gen.sh on a CA free host?");

    runCipherTest(SSL_TXT_AES128, SSL_TXT_MD5);
    runCipherTest(SSL_TXT_AES256, SSL_TXT_MD5);
    runCipherTest(SSL_TXT_AES128, SSL_TXT_SHA);
    runCipherTest(SSL_TXT_AES256, SSL_TXT_SHA);
    runCipherTest(SSL_TXT_AES128, SSL_TXT_SHA256);
    runCipherTest(SSL_TXT_AES256, SSL_TXT_SHA256);
test.footer; }

// not to support yet
//unittest { test.header("crypt: self signed certificates check behavior"); test.footer(); }
//unittest { test.header("crypt: signed certificates check behavior"); test.footer(); }
//unittest { test.header("crypt: invalid certificates check behavior"); test.footer(); }
//unittest { test.header("crypt: revoked certificates check behavior"); test.footer(); }