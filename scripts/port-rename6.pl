#!/usr/bin/perl -pi
# Pass 6: DustParticleOptions Vector3f->packed int; Level.random/isClientSide accessors.
# DustParticleOptions(new Vector3f(r,g,b), scale) -> DustParticleOptions(packed int, scale)
s{new\s+DustParticleOptions\(\s*new\s+Vector3f\(\s*([^(),]+?)\s*,\s*([^(),]+?)\s*,\s*([^(),]+?)\s*\)\s*,\s*([^,;()]+?)\s*\)}
 {sprintf("new DustParticleOptions(((int)(%s*255)<<16)|((int)(%s*255)<<8)|(int)(%s*255), %s)", $1,$2,$3,$4)}ge;
# protected Level.random field -> getRandom()
s/\.random(?![\w(])/.getRandom()/g;
# private Level.isClientSide field -> isClientSide() method (not already a call)
s/\.isClientSide\b(?!\s*\()/.isClientSide()/g;
