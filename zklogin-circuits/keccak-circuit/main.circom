pragma circom 2.1.6;

include "./vocdoni-keccak/keccak.circom";
include "../circomlib/circuits/bitify.circom";

template Main () {
    signal input a0e;
    signal input a1m;
    signal input salt;
    signal output out[2];

    component n2b[3];
    for(var i = 0; i < 3; i++){
        n2b[i] = Num2Bits(256);
    }
    n2b[0].in <== a0e;
    n2b[1].in <== a1m;
    n2b[2].in <== salt;

    signal d;

    d <-- 1;

    
    signal reverse[256*3];
    signal hash_input[256*3];
    for(var i = 0; i < 256; i++) {
        reverse[i] <== n2b[0].out[255-i]*d;
        reverse[i+256] <== n2b[1].out[255-i]*d;
        reverse[i+512] <== n2b[2].out[255-i]*d;
    }

    for (var i = 0; i < 256*3 / 8; i += 1) {
      for (var j = 0; j < 8; j++) {
        hash_input[8*i + j] <== reverse[8*i + (7-j)];
      }
    }

    component hash = Keccak(256*3, 256);

    hash.in <== hash_input;

    signal left[128];
    signal right[128];

    signal bytes[256];

    for (var i = 0; i < 256/ 8; i += 1) {
      for (var j = 0; j < 8; j++) {
        bytes[255-(8*i + j)] <== hash.out[8*i + (7-j)];
      }
    }

    for (var i = 0; i < 128; i++) {
      left[i] <== bytes[i+128];
      right[i] <== bytes[i];
    }

    component b2n[2];
    for(var i = 0; i < 2; i++){
        b2n[i] = Bits2Num(128);
    }

    b2n[0].in <== left;
    b2n[1].in <== right;

    out[0] <== b2n[0].out;
    out[1] <== b2n[1].out;

}

component main { public [ a0e, a1m] } = Main();
