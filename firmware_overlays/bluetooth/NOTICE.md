SPDX-License-Identifier: GPL-3.0-or-later

Bluetooth HCI responder and ARM glue are adapted from nortido/NGage-MiSTer,
revision 4b8480148db15d432e2abf6a6956832c91d9cf55, hps/guest/bt_*.
Source: https://github.com/nortido/NGage-MiSTer/tree/4b8480148db15d432e2abf6a6956832c91d9cf55/hps/guest

The responder replaces the NEM-4 v4.03 BTLDD transmit/completion path, stores
local HCI settings and answers initialization/inquiry requests without a peer.
It does not implement a radio or real Bluetooth links. Original kernel ring and
completion functions remain in use. The payload stays below the NOS injection
range at511B6000. No NOS dependency, C: routing or UI/startup edits are included.
The package includes a shared primary-checksum bypass while either overlay is
ON; both OFF restore the original descriptor. Original service files stay intact.
