# JPEG bitmap hotspot performance baseline

These are fixed-work original-code RTL cycles, not SPMark points or whole-JPEG
latency. Baseline100 applies only to this four-case suite. Both synthetic I:D
profiles0:0 and2:9 produce the same warm medians; measured windows have no
external requests. Seven checked windows (two warm-ups/five samples), two exact
repeats per profile. See [profile and qualification](spmark-jpeg-profile.md).

| Revision | 8×8 JPEG pixels, mode10 | 8×8 random, mode10 | 8×8 random, mode8 | 16×8 JPEG pixels, mode10 | Index |
| --- | ---: | ---: | ---: | ---: | ---: |
| baseline — current CPU1abf0db, snapshotf1791df | 118705 | 118720 | 117760 | 234273 |100 |
| pre-store reference — d4f2a8 | 122793 | 122808 | 121848 | 242265 |96.6720 |

Mode10 is the original native12-bit RGB converter used by this path; mode8
is a24-bit control. Inputs are cropped pixels independently decoded from the
original640×480 TEST.JPG, or fixed random vectors. This does not validate a
full JPEG decoder against Pillow. The original Symbian bitmap routine and its
native helper/converter instructions run unchanged at original ROM addresses.

Current throughput versus pre-store: diffuse_m10_8x8_jpeg +3.444%, diffuse_m10_8x8_random +3.443%, diffuse_m8_8x8_random +3.471%, diffuse_m10_16x8_jpeg +3.411%.

[Evidence](evidence/spmark-jpeg-profile-20261115.json). Raw generated binaries,
images and complete counters stay in build/sim/jpeg-payload/error-diffusion-20261115-v2.
