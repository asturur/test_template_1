# JPEG bitmap hotspot performance baseline

These are fixed-work original-code RTL cycles, not SPMark points or whole-JPEG
latency. Baseline100 applies only to this four-case suite. Both synthetic I:D
profiles0:0 and2:9 produce the same warm medians; measured windows have no
external requests. Seven checked windows (two warm-ups/five samples), two exact
repeats per profile. See [profile and qualification](spmark-jpeg-profile.md).

| Revision | 8×8 JPEG pixels, mode10 | 8×8 random, mode10 | 8×8 random, mode8 | 16×8 JPEG pixels, mode10 | Index |
| --- | ---: | ---: | ---: | ---: | ---: |
| baseline — current CPU1abf0db, snapshotf1791df | 118705 | 118720 | 117760 | 234273 |100 |
| completion-overlap | 117970 | 117985 | 117025 | 232802 |100.6265 |
| legacy-delay-removed | 113957 | 113973 | 112956 | 224845 |104.1944 |
| thumb-target-address | 111449 | 111465 | 110320 | 219849 |106.5810 |
| admission-pre-read | 108853 | 108869 | 107724 | 214749 |109.1267 |
| block-transfer-fusion | 107047 | 107063 | 105742 | 211231 |111.0129 |
| pre-store reference — d4f2a8 | 122793 | 122808 | 121848 | 242265 |96.6720 |

Mode10 is the original native12-bit RGB converter used by this path; mode8
is a24-bit control. Inputs are cropped pixels independently decoded from the
original640×480 TEST.JPG, or fixed random vectors. This does not validate a
full JPEG decoder against Pillow. The original Symbian bitmap routine and its
native helper/converter instructions run unchanged at original ROM addresses.

At the first bitmap baseline, throughput versus pre-store: diffuse_m10_8x8_jpeg +3.444%, diffuse_m10_8x8_random +3.443%, diffuse_m8_8x8_random +3.471%, diffuse_m10_16x8_jpeg +3.411%.

[Evidence](evidence/spmark-jpeg-profile-20261115.json). Raw generated binaries,
images and complete counters stay in build/sim/jpeg-payload/error-diffusion-20261115-v2.

Completion overlap adds about0.63% in this suite. All8groups/two repeats,
8unprofiled counter matches and8broken pixel/object controls pass. This does not
establish a native deadline pass. [Evidence](evidence/spmark-jpeg-completion-overlap-20261115.json).

Legacy P0 removal gains3.5457% over completion overlap, with all original
outputs, exact repeats and unprofiled-counter controls accepted. This remains
a bitmap-conversion kernel result; native JPEG deadline is unpassed.
[Evidence](evidence/cpu-postalu-trim-20261116.json).

Thumb target-address normalization gains2.2906% over P0 removal; all8groups,
repeats, unprofiled matches and8output/object controls pass. Native JPEG deadline
remains unverified. [Evidence](evidence/thumb-prediction-address-20261116.json).

Admission-edge pre-read reuse gains2.3885% over Thumb target-address and removes
2,973 data-wait clocks per8×8block. Native JPEG deadline remains unverified.
[Evidence](evidence/cache-admission-probe-20261116.json).
