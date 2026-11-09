NOS compatibility guest code is derived from nortido/NGage-MiSTer revision
4b8480148db15d432e2abf6a6956832c91d9cf55, hps/guest/nos_*.
Original source: https://github.com/nortido/NGage-MiSTer/tree/4b8480148db15d432e2abf6a6956832c91d9cf55/hps/guest
SPDX-License-Identifier: GPL-3.0-or-later

bootstrap.S adapts the reference's injected service-table initializer in
hps/lib/ngl_svcrom.c into readable assembly. It does not include Nokia code.
The replacement implements narrow accessory/light/vibration replies, not a
cellular network, SIM, calls or SMS. Its kernel ABI is specific to NEM-4 4.03.
No Nokia firmware is included here. The pack builder derives original words
from the user's audited original service files. NOS Compatibility ON also
skips the primary firmware checksum using the reference's absent-descriptor
path. Both NOS and Bluetooth OFF restore the descriptor and checksum behavior;
original digest words and files on disk are never changed.

The initialization callback installed at guest global800004AC is a no-op, as
in the pinned reference; it is separate from the NOS channel constructor.

Hardware testing found that the fake bootstrap prevents the Nokia logo. Normal
packages retain original NOS startup and replace only the driver. bootstrap.S
is preserved solely for explicit diagnostic builds; it is not the default.
