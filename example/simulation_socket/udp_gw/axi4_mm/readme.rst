AXI4 and APB memories on UDP
============================

A simulator that exposes two memory-mapped buses as UDP ports, to be
driven from the host (acrobe, or any program that speaks the frame
formats below):

========  ==========================================================
UDP port  Bus
========  ==========================================================
4250      64 KiB ``axi4_mm_full_ram`` behind ``axi4_mm_on_stream``
          (32-bit address, 32-bit data, 2 ID bits, bursts up to 16)
4251      4 KiB ``apb_ram`` behind ``apb_stream_bridge``
          (16-bit address, 32-bit data)
========  ==========================================================

The simulation runs until killed.

Build and run::

  gbs project -f project.gbs.yaml build simulation
  ./tb

Then, from another terminal::

  acrobe run demo.py

Building such a simulator
-------------------------

Each port is one ``axi4_stream_udp_gateway`` on a one-byte stream: a
received datagram becomes one frame on ``rx_o``, a frame given to
``tx_i`` is sent back as one datagram to the last peer heard from. The
gateway needs the VHPIDIRECT UDP socket, hence GHDL. Put whatever
stream endpoint on the frames:

* ``apb_stream_bridge`` takes one-byte frames directly.
* ``axi4_mm_on_stream`` routes on the stream ID: an
  ``axi4_stream_meta_unpacker`` / ``axi4_stream_meta_packer`` pair with
  ``meta_elements_c => "i"`` turns it into a leading datagram byte. Use
  a 3-bit stream ID so that byte is the channel number. Only the
  ``master_o`` / ``master_i`` side is used, the local ``slave_i`` side is
  tied idle.

More ports are more gateway instances with distinct ``bind_port_c``;
sample I/O streams would be one more gateway feeding a stream sink or
source.

Driving the AXI4 port
---------------------

From acrobe, the path is::

  udp/127.0.0.1:4250/nsl_axi4_mm(id_width=2,max_length=16,burst=1)

The options mirror ``nsl_amba.axi4_mm.config()`` and must match
``mm_config_c``, as they define field widths on the wire:
``address_width`` (default 32), ``data_bus_width`` (32), ``id_width``
(0), ``user_width`` (0), ``max_length`` (1), ``size``, ``burst``,
``cache``, ``lock``, ``qos``, ``region`` (false). Host-side options are
``id``, ``prot``, ``max_burst``, ``window`` and ``timeout``. The node is
an acrobe memory bus (``mem_read`` / ``mem_write`` of any length and
alignment, ``read8/16/32`` / ``write8/16/32``).

A client in another language (C, ...) sends and receives datagrams made
of one channel byte followed by channel beats:

========  =======  ============================  ===================
Byte      Channel  Direction                     Beats in the frame
========  =======  ============================  ===================
0x00      B        simulator to client           1
0x01      AW       client to simulator           1
0x02      AR       client to simulator           1
0x03      R        simulator to client           burst length
0x04      W        client to simulator           burst length
========  =======  ============================  ===================

Each beat is a bit vector packed LSB first, zero-padded to whole bytes
and sent least significant byte first. For this simulator's bus:

* AW / AR, 6 bytes: ``addr[31:0]``, ``prot[34:32]``, ``burst[36:35]``
  (INCR = 1), ``len[40:37]`` (beats - 1), ``id[42:41]``;
* W, 5 bytes per beat: 4 data bytes (lane 0 first), then ``strb`` in
  bits 3:0 of the fifth byte (bit i enables lane i);
* B, 1 byte: ``resp[1:0]``, ``id[3:2]``;
* R, 5 bytes per beat: 4 data bytes, then ``resp`` in bits 1:0 and
  ``id`` in bits 3:2 of the fifth byte.

``resp`` is OKAY = 0, EXOKAY = 1, SLVERR = 2, DECERR = 3. The general
layout, with optional fields, is documented on ``axi4_mm_on_stream`` in
``nsl_amba.mm_stream_adapter``.

A client must:

* send each W frame right after its AW frame, as the simulator forwards
  frames one at a time and a W frame waiting for its address would block
  everything behind it;
* keep a single ID, or match responses per ID, since AXI only orders
  responses of a same ID;
* wait for write responses before reading what it wrote (and the
  converse), since reads and writes are not ordered against each other;
* start bursts on a bus word, keep them under the configured length and
  inside a 4 KiB page, and mask partial words with ``strb``.

For instance, writing ``11 22 33 44`` at 0x100 with ID 1 is the two
datagrams ``01 00 01 00 00 08 02`` and ``04 11 22 33 44 0f``, answered by
``00 04``.

Driving the APB port
--------------------

From acrobe, the path is::

  udp/127.0.0.1:4251/nsl_apb(address_width=16,data_bus_width=32,burst_length_l2=4)

The three options are required and must match the bridge's generics
(``apb_config_c`` address and data widths, ``burst_length_l2_c``), as
they define field widths on the wire. Host-side options are
``max_write`` (words per write command), ``window`` and ``timeout``.
The node is an acrobe memory bus (``mem_read`` of any length and
alignment, ``mem_write`` of whole aligned words, ``read8/16/32``,
``write32``) with an ``identify()`` method. The bridge has no byte
strobes: a partial-word write is refused rather than turned into a
read-modify-write.

A client in another language sends one command per datagram,
multi-byte fields little-endian, and gets one datagram back ending with
a status byte (bit 0: PSLVERR on one of the command's transfers, or a
malformed command):

* identify ``ff`` returns ``apb_ram``, then the status;
* read ``80``, 2 address bytes, 1 byte of word count - 1 (up to 15),
  returns the words, then the status;
* write ``00``, 2 address bytes, whole words, returns the status.

For instance, writing ``00 11 22 33`` then ``44 55 66 77`` at 0x40 is
``00 40 00 00 11 22 33 44 55 66 77``, answered by ``00``; reading them
back is ``80 40 00 01``, answered by ``00 11 22 33 44 55 66 77 00``.

The bridge answers commands one at a time, in order, with nothing in
an answer naming its command: a client matches answers to commands in
order. The count keeps ``burst_length_l2_c`` bits, so a larger count
wraps. A failing transfer does not stop the command, the other words
are still moved.
