library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_amba;
use nsl_amba.axi4_mm.all;
use nsl_amba.axi4_stream.all;

package mm_stream_adapter is

  -- AXI4-MM tunnel over a pair of AXI4-Streams.
  --
  -- Serializes the five channels of an AXI4 bus on tx_o and replays the
  -- channels received on rx_i. Two instances back to back bridge a bus.
  -- Each instance has both ends of the tunnel:
  --
  -- * slave_i/slave_o: a local master's AW, W and AR are sent on tx_o;
  --   B and R received on rx_i are returned to it,
  -- * master_o/master_i: AW, W and AR received on rx_i are issued to a
  --   local slave; its B and R are sent on tx_o.
  --
  -- Tie the unused side to idle defaults. The tunnel does not look at
  -- IDs or bursts; transactions are forwarded as they are.
  --
  -- stream_config_c must have last and ready, and at least 3 id bits.
  -- The channel of a frame is carried in the 3 upper bits of the stream
  -- ID: B=0, AW=1, AR=2, R=3, W=4. Lower ID bits are zero on tx_o and
  -- ignored on rx_i.
  --
  -- Each channel beat is packed as a bit vector, LSB first, in the order
  -- below, zero-padded to whole bytes and sent least significant byte
  -- first. Optional fields have no bits when mm_config_c omits them:
  --
  -- * AW/AR: addr, prot(3), size(3), burst(2), cache(4), len, lock(1),
  --   id, qos(4), region(4), user,
  -- * W: data (lane 0 first), strb (bit i for lane i), user,
  -- * B: resp(2), id, user,
  -- * R: data, resp(2), id, user.
  --
  -- burst is present when mm_config_c has burst and a length field.
  -- With a stream wider than one byte, each beat vector is also padded
  -- to a whole number of stream beats, padding bytes having keep low.
  -- Frames are one beat on AW, AR and B, and one burst on W and R, the
  -- frame end being WLAST/RLAST.
  --
  -- Received frames are forwarded one at a time: a frame whose channel
  -- does not progress stalls every frame behind it. A peer must send
  -- the W frame of a write right after its AW frame.
  --
  -- On a byte transport, axi4_stream_meta_packer and
  -- axi4_stream_meta_unpacker (meta_elements_c => "i") carry the stream
  -- ID as a prefix byte. With a 3-bit stream ID, that byte is the
  -- channel number.
  component axi4_mm_on_stream is
    generic (
      mm_config_c : nsl_amba.axi4_mm.config_t;
      stream_config_c : nsl_amba.axi4_stream.config_t
      );
    port (
      clock_i: in std_ulogic;
      reset_n_i: in std_ulogic;

      slave_i : in nsl_amba.axi4_mm.master_t;
      slave_o : out nsl_amba.axi4_mm.slave_t;

      master_o : out nsl_amba.axi4_mm.master_t;
      master_i : in nsl_amba.axi4_mm.slave_t;
      
      rx_i : in nsl_amba.axi4_stream.master_t;
      rx_o : out nsl_amba.axi4_stream.slave_t;

      tx_o : out nsl_amba.axi4_stream.master_t;
      tx_i : in nsl_amba.axi4_stream.slave_t
      );
  end component;

end package;
