//
//  sha256.vsh
//  ExploringGPGPU
//

#version 300 es

#define BYTESWAP(x) ((x) >> 24) | (((x) >> 8) & 0xff00U) | (((x) << 8) & 0xff0000U) | (x) << 24
#define ROTRIGHT(a,b) (((a) >> (b)) | ((a) << (32-(b))))

#define CH(x,y,z) (((x) & (y)) ^ (~(x) & (z)))
#define MAJ(x,y,z) (((x) & (y)) ^ ((x) & (z)) ^ ((y) & (z)))
#define EP0(x) (ROTRIGHT(x,2) ^ ROTRIGHT(x,13) ^ ROTRIGHT(x,22))
#define EP1(x) (ROTRIGHT(x,6) ^ ROTRIGHT(x,11) ^ ROTRIGHT(x,25))
#define SIG0(x) (ROTRIGHT(x,7) ^ ROTRIGHT(x,18) ^ ((x) >> 3))
#define SIG1(x) (ROTRIGHT(x,17) ^ ROTRIGHT(x,19) ^ ((x) >> 10))

uint k[64] = uint[64](
    0x428a2f98U, 0x71374491U, 0xb5c0fbcfU, 0xe9b5dba5U, 0x3956c25bU, 0x59f111f1U, 0x923f82a4U, 0xab1c5ed5U,
    0xd807aa98U, 0x12835b01U, 0x243185beU, 0x550c7dc3U, 0x72be5d74U, 0x80deb1feU, 0x9bdc06a7U, 0xc19bf174U,
    0xe49b69c1U, 0xefbe4786U, 0x0fc19dc6U, 0x240ca1ccU, 0x2de92c6fU, 0x4a7484aaU, 0x5cb0a9dcU, 0x76f988daU,
    0x983e5152U, 0xa831c66dU, 0xb00327c8U, 0xbf597fc7U, 0xc6e00bf3U, 0xd5a79147U, 0x06ca6351U, 0x14292967U,
    0x27b70a85U, 0x2e1b2138U, 0x4d2c6dfcU, 0x53380d13U, 0x650a7354U, 0x766a0abbU, 0x81c2c92eU, 0x92722c85U,
    0xa2bfe8a1U, 0xa81a664bU, 0xc24b8b70U, 0xc76c51a3U, 0xd192e819U, 0xd6990624U, 0xf40e3585U, 0x106aa070U,
    0x19a4c116U, 0x1e376c08U, 0x2748774cU, 0x34b0bcb5U, 0x391c0cb3U, 0x4ed8aa4aU, 0x5b9cca4fU, 0x682e6ff3U,
    0x748f82eeU, 0x78a5636fU, 0x84c87814U, 0x8cc70208U, 0x90befffaU, 0xa4506cebU, 0xbef9a3f7U, 0xc67178f2U
);

in uvec4 block0;
in uvec4 block1;
out uvec4 digest[2];

void main() {
    uint h0,h1,h2,h3,h4,h5,h6,h7,w[64],a,b,c,d,e,f,g,h,t1,t2;
    int i;

    // Initialize hash values:
    // (first 32 bits of the fractional parts of the square roots of the first 8 primes 2..19):
    h0 = 0x6a09e667U;
    h1 = 0xbb67ae85U;
    h2 = 0x3c6ef372U;
    h3 = 0xa54ff53aU;
    h4 = 0x510e527fU;
    h5 = 0x9b05688cU;
    h6 = 0x1f83d9abU;
    h7 = 0x5be0cd19U;

    // create a 64-entry message schedule array w[0..63] of 32-bit words
    // (The initial values in w[0..63] don't matter, so many implementations zero them here)
    // copy chunk into first 16 words w[0..15] of the message schedule array
    w[0]  = BYTESWAP(block0.x);
    w[1]  = BYTESWAP(block0.y);
    w[2]  = BYTESWAP(block0.z);
    w[3]  = BYTESWAP(block0.w);
    w[4]  = BYTESWAP(block1.x);
    w[5]  = BYTESWAP(block1.y);
    w[6]  = BYTESWAP(block1.z);
    w[7]  = BYTESWAP(block1.w);
    w[8]  = 0x80000000U;
    w[9]  = 0U;
    w[10] = 0U;
    w[11] = 0U;
    w[12] = 0U;
    w[13] = 0U;
    w[14] = 0U;
    w[15] = 0x100U;

    // Extend the first 16 words into the remaining 48 words w[16..63] of the message schedule array:
    for (i = 16; i < 64; i++)
        w[i] = SIG1(w[i-2]) + w[i-7] + SIG0(w[i-15]) + w[i-16];

    // Initialize working variables to current hash value:
    a = h0;
    b = h1;
    c = h2;
    d = h3;
    e = h4;
    f = h5;
    g = h6;
    h = h7;

    // Compression function main loop:
    for (i = 0; i < 64; i++) {
        t1 = h + EP1(e) + CH(e,f,g) + k[i] + w[i];
        t2 = EP0(a) + MAJ(a,b,c);
        h = g;
        g = f;
        f = e;
        e = d + t1;
        d = c;
        c = b;
        b = a;
        a = t1 + t2;
    }

    // Add the compressed chunk to the current hash value:
    h0 += a;
    h1 += b;
    h2 += c;
    h3 += d;
    h4 += e;
    h5 += f;
    h6 += g;
    h7 += h;

    // Produce the final hash value (big-endian):
    digest[0].x = BYTESWAP(h0);
    digest[0].y = BYTESWAP(h1);
    digest[0].z = BYTESWAP(h2);
    digest[0].w = BYTESWAP(h3);
    digest[1].x = BYTESWAP(h4);
    digest[1].y = BYTESWAP(h5);
    digest[1].z = BYTESWAP(h6);
    digest[1].w = BYTESWAP(h7);
}
