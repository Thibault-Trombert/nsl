library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_bnoc, nsl_video;

-- ADV7511 is an HDMI transmitter taking parallel video with separate
-- syncs, configured over I2C.
package adv7511 is

  -- Main register map address with PD/AD pin pulled low.  Pulled high,
  -- it is 0x3d.
  constant i2c_saddr_default_c : unsigned(7 downto 1) := "0111001";

  -- Picture aspect ratio stated in the AVI infoframe.
  type aspect_t is (
    ASPECT_4_3,
    ASPECT_16_9
    );

  -- S/PDIF audio sample rate, it selects the N value of the audio
  -- clock regeneration.
  type audio_rate_t is (
    AUDIO_RATE_32K,
    AUDIO_RATE_44K1,
    AUDIO_RATE_48K,
    AUDIO_RATE_88K2,
    AUDIO_RATE_96K,
    AUDIO_RATE_176K4,
    AUDIO_RATE_192K
    );

  -- Drives an ADV7511 from a pixel stream.
  --
  -- Video goes to the chip as YCbCr 4:2:2 with eight bits per
  -- component on a 16-bit bus with separate syncs (input ID 1, style
  -- 1, right justified): data_o(15 downto 8) carries chroma,
  -- data_o(7 downto 0) carries luma, and the bus is wired to the chip
  -- D[23:8] inputs.  The chip converts it to full range RGB, which
  -- goes out either as DVI or as HDMI.
  --
  -- Raster timings come in as pseudo-constant ports, as for
  -- nsl_dvi.encoder.dvi_10_encoder.  The raster owns the timing and
  -- the stream follows it: the driver locks onto the first frame the
  -- stream opens, and sends black in place of pixels while it does
  -- not hold.  config_c must be YCBCR422, eight bits per component,
  -- limited range.  Its colorimetry selects the conversion matrix.
  --
  -- The chip powers its outputs down and loses most of its
  -- configuration whenever no sink is plugged in.  The driver reads
  -- the hot plug state when the chip interrupts, or every 100ms
  -- otherwise, and configures the chip whenever a sink appears.
  -- Pseudo-constant control inputs (aspect, hdmi, audio) are sampled
  -- when configuration starts; changing them takes effect on the next
  -- plug.
  --
  -- Audio is taken by the chip from its S/PDIF input, which is not
  -- handled here.  Audio is only sent in HDMI mode.
  component adv7511_driver is
    generic(
      clock_i_hz_c : natural;
      config_c : nsl_video.pixel_stream.config_t;
      i2c_saddr_c : unsigned(7 downto 1) := i2c_saddr_default_c;
      -- Input clock delay setting (register 0xba), 3 is no delay, each
      -- step is 0.4ns.
      clock_delay_c : natural range 0 to 7 := 3
      );
    port(
      -- Control domain
      clock_i : in std_ulogic;
      reset_n_i : in std_ulogic;

      -- Chip interrupt line, synchronous to clock_i.
      irq_n_i : in std_ulogic := '1';

      -- Framed master port to a nsl_i2c.transactor.transactor_framed_controller.
      cmd_o : out nsl_bnoc.framed.framed_req;
      cmd_i : in nsl_bnoc.framed.framed_ack;
      rsp_i : in nsl_bnoc.framed.framed_req;
      rsp_o : out nsl_bnoc.framed.framed_ack;

      aspect_i : in aspect_t := ASPECT_16_9;
      -- HDMI mode, DVI otherwise.
      hdmi_i : in std_ulogic := '1';
      audio_enable_i : in std_ulogic := '0';
      audio_rate_i : in audio_rate_t := AUDIO_RATE_48K;

      -- A sink is plugged in.
      hpd_o : out std_ulogic;
      -- Chip is powered and configured.
      ready_o : out std_ulogic;

      -- Video domain
      pixel_clock_i : in std_ulogic;
      pixel_reset_n_i : in std_ulogic;

      -- Vertical frame parameters
      v_fp_m1_i : in unsigned;
      v_sync_m1_i : in unsigned;
      v_bp_m1_i : in unsigned;
      v_act_m1_i : in unsigned;

      -- Horizontal frame parameters
      h_fp_m1_i : in unsigned;
      h_sync_m1_i : in unsigned;
      h_bp_m1_i : in unsigned;
      h_act_m1_i : in unsigned;

      -- Sync values
      vsync_i : in std_ulogic := '1';
      hsync_i : in std_ulogic := '1';

      pixel_i : in nsl_video.pixel_stream.master_t;
      pixel_o : out nsl_video.pixel_stream.slave_t;

      synced_o : out std_ulogic;

      -- Chip video input pins
      clock_o : out std_ulogic;
      de_o : out std_ulogic;
      hsync_o : out std_ulogic;
      vsync_o : out std_ulogic;
      data_o : out std_ulogic_vector(15 downto 0)
      );
  end component;

end package;
