library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_bnoc, nsl_video, nsl_i2c, nsl_data, nsl_io, nsl_math, nsl_synthesis;
use work.adv7511.all;
use nsl_data.bytestream.all;
use nsl_video.pixel_stream.all;

entity adv7511_driver is
  generic(
    clock_i_hz_c : natural;
    config_c : nsl_video.pixel_stream.config_t;
    i2c_saddr_c : unsigned(7 downto 1) := i2c_saddr_default_c;
    clock_delay_c : natural range 0 to 7 := 3
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    irq_n_i : in std_ulogic := '1';

    cmd_o : out nsl_bnoc.framed.framed_req;
    cmd_i : in nsl_bnoc.framed.framed_ack;
    rsp_i : in nsl_bnoc.framed.framed_req;
    rsp_o : out nsl_bnoc.framed.framed_ack;

    aspect_i : in aspect_t := ASPECT_16_9;
    hdmi_i : in std_ulogic := '1';
    audio_enable_i : in std_ulogic := '0';
    audio_rate_i : in audio_rate_t := AUDIO_RATE_48K;

    hpd_o : out std_ulogic;
    ready_o : out std_ulogic;

    pixel_clock_i : in std_ulogic;
    pixel_reset_n_i : in std_ulogic;

    v_fp_m1_i : in unsigned;
    v_sync_m1_i : in unsigned;
    v_bp_m1_i : in unsigned;
    v_act_m1_i : in unsigned;

    h_fp_m1_i : in unsigned;
    h_sync_m1_i : in unsigned;
    h_bp_m1_i : in unsigned;
    h_act_m1_i : in unsigned;

    vsync_i : in std_ulogic := '1';
    hsync_i : in std_ulogic := '1';

    pixel_i : in nsl_video.pixel_stream.master_t;
    pixel_o : out nsl_video.pixel_stream.slave_t;

    synced_o : out std_ulogic;

    clock_o : out std_ulogic;
    de_o : out std_ulogic;
    hsync_o : out std_ulogic;
    vsync_o : out std_ulogic;
    data_o : out std_ulogic_vector(15 downto 0)
    );
end entity;

architecture beh of adv7511_driver is

  -- Control domain

  -- Chip I2C address is only decided 200ms after power up.
  constant startup_cycles_c : natural := clock_i_hz_c / 5;
  -- Hot plug state is polled this often when no interrupt comes.
  constant poll_cycles_c : natural := clock_i_hz_c / 10;
  constant timer_max_c : natural := nsl_math.arith.max(startup_cycles_c, poll_cycles_c);

  constant reg_irq_status_c : byte := x"96";
  constant reg_irq_status_hpd_c : natural := 7;
  constant reg_status_c : byte := x"42";
  constant reg_status_hpd_c : natural := 6;
  -- HPD and monitor sense
  constant irq_clear_c : byte := x"c0";

  -- Pseudo-constant inputs, as sampled when configuration starts.
  type setup_t is
  record
    aspect: aspect_t;
    hdmi: boolean;
    audio_enable: boolean;
    audio_rate: audio_rate_t;
  end record;

  -- Conversion from limited range YCbCr to full range RGB, registers
  -- 0x18 to 0x2f.
  constant csc_bt709_c : byte_string(0 to 23) := from_hex(
    "e73404ad00001c1b"
    & "1ddc04ad1f240135"
    & "000004ad087c1b77");
  constant csc_bt601_c : byte_string(0 to 23) := from_hex(
    "e66904ac00001c81"
    & "1cbc04ad1e6e0220"
    & "1ffe04ad081a1ba9");

  function csc_table return byte_string is
  begin
    case config_c.colorimetry is
      when COLORIMETRY_BT601 => return csc_bt601_c;
      when COLORIMETRY_BT709 => return csc_bt709_c;
    end case;
  end function;

  constant csc_c : byte_string(0 to 23) := csc_table;

  function audio_n(rate: audio_rate_t) return unsigned is
  begin
    case rate is
      when AUDIO_RATE_32K => return to_unsigned(4096, 24);
      when AUDIO_RATE_44K1 => return to_unsigned(6272, 24);
      when AUDIO_RATE_48K => return to_unsigned(6144, 24);
      when AUDIO_RATE_88K2 => return to_unsigned(12544, 24);
      when AUDIO_RATE_96K => return to_unsigned(12288, 24);
      when AUDIO_RATE_176K4 => return to_unsigned(25088, 24);
      when AUDIO_RATE_192K => return to_unsigned(24576, 24);
    end case;
  end function;

  constant config_entry_count_c : natural := 47;

  -- Register writes making the configuration, as address, data.
  function config_entry(index: natural range 0 to config_entry_count_c - 1;
                        setup: setup_t) return byte_string
  is
    variable n: unsigned(23 downto 0);
    variable ret: byte_string(0 to 1);
  begin
    n := audio_n(setup.audio_rate);

    case index is
      -- Power up, no sync adjustment
      when 0 => ret := from_hex("4110");
      -- Fixed registers that must be set after power up
      when 1 => ret := from_hex("9803");
      when 2 => ret := from_hex("9ae0");
      when 3 => ret := from_hex("9c30");
      when 4 => ret := from_hex("9d61");
      when 5 => ret := from_hex("a2a4");
      when 6 => ret := from_hex("a3a4");
      when 7 => ret := from_hex("e0d0");
      when 8 => ret := from_hex("f900");
      -- Input ID 1: YCbCr 4:2:2, separate syncs
      when 9 => ret := from_hex("1501");
      -- 4:4:4 output, 8-bit input, style 1
      when 10 => ret := from_hex("1638");
      -- Syncs passed through, input aspect
      when 11 =>
        if setup.aspect = ASPECT_16_9 then
          ret := from_hex("1702");
        else
          ret := from_hex("1700");
        end if;
      -- Color space conversion to full range RGB
      when 12 to 35 =>
        ret(0) := to_byte(16#18# + index - 12);
        ret(1) := csc_c(index - 12);
      -- Right justified 4:2:2 input
      when 36 => ret := from_hex("4808");
      -- AVI infoframe: RGB, active format present
      when 37 => ret := from_hex("5510");
      -- AVI infoframe: picture aspect, active format same as picture
      when 38 =>
        if setup.aspect = ASPECT_16_9 then
          ret := from_hex("5628");
        else
          ret := from_hex("5618");
        end if;
      -- AVI infoframe: full range RGB
      when 39 => ret := from_hex("5708");
      when 40 =>
        ret(0) := x"ba";
        ret(1) := std_ulogic_vector(to_unsigned(clock_delay_c, 3)) & "00000";
      -- Audio clock regeneration N
      when 41 =>
        ret(0) := x"01";
        ret(1) := std_ulogic_vector(n(23 downto 16));
      when 42 =>
        ret(0) := x"02";
        ret(1) := std_ulogic_vector(n(15 downto 8));
      when 43 =>
        ret(0) := x"03";
        ret(1) := std_ulogic_vector(n(7 downto 0));
      -- Audio select S/PDIF, automatic CTS
      when 44 => ret := from_hex("0a10");
      -- S/PDIF enable
      when 45 =>
        if setup.audio_enable then
          ret := from_hex("0b8e");
        else
          ret := from_hex("0b0e");
        end if;
      -- HDMI or DVI mode, last so that the link starts configured
      when others =>
        if setup.hdmi then
          ret := from_hex("af06");
        else
          ret := from_hex("af04");
        end if;
    end case;

    return ret;
  end function;

  type state_t is (
    ST_RESET,
    ST_STARTUP,
    ST_IRQ_READ,
    ST_IRQ_CHECK,
    ST_IRQ_CLEAR,
    ST_HPD_READ,
    ST_HPD_CHECK,
    ST_CONFIG,
    ST_WAIT,
    -- A register access, going back to r.next_state once done
    ST_ACCESS_CMD,
    ST_ACCESS_RSP
    );

  type regs_t is
  record
    state, next_state: state_t;
    timer: natural range 0 to timer_max_c;
    index: natural range 0 to config_entry_count_c;
    setup: setup_t;
    hpd, hpd_event, configured: boolean;

    write: boolean;
    addr, data: byte;
  end record;

  signal r, rin: regs_t;

  signal access_cmd_valid_s, access_rsp_ready_s, access_write_s: std_ulogic;
  signal access_ready_s, access_valid_s, access_error_s: std_ulogic;
  signal access_rdata_s: byte_string(0 to 0);

  -- Video domain

  constant h_width_c : integer := nsl_math.arith.max(
    h_fp_m1_i'length, nsl_math.arith.max(
    h_sync_m1_i'length, nsl_math.arith.max(
    h_bp_m1_i'length, h_act_m1_i'length)));
  constant v_width_c : integer := nsl_math.arith.max(
    v_fp_m1_i'length, nsl_math.arith.max(
    v_sync_m1_i'length, nsl_math.arith.max(
    v_bp_m1_i'length, v_act_m1_i'length)));

  subtype h_count_t is unsigned(h_width_c-1 downto 0);
  subtype v_count_t is unsigned(v_width_c-1 downto 0);

  type raster_state_t is (
    RS_FP,
    RS_SYNC,
    RS_BP,
    RS_ACT
    );

  type pixel_regs_t is
  record
    v_left: v_count_t;
    v_state: raster_state_t;
    h_left: h_count_t;
    h_state: raster_state_t;

    -- Pins, one cycle behind the raster
    de, hsync, vsync: std_ulogic;
    data: std_ulogic_vector(15 downto 0);
  end record;

  signal pr, prin: pixel_regs_t;

  signal sof_s, sol_s, ready_s, valid_s: std_ulogic;
  signal stream_pixel_s: nsl_video.pixel_stream.pixel_t;
  signal forward_s: nsl_io.diff.diff_pair;

begin

  colorspace_check: nsl_synthesis.assertion.synth_assert
    generic map(
      message_c => "ADV7511 driver takes YCbCr 4:2:2, eight bits, limited range",
      condition_c => config_c.colorspace = COLORSPACE_YCBCR422
      and config_c.component_bits = 8
      and config_c.quantization = QUANTIZATION_LIMITED
      and config_c.pixel_count = 1
      )
    port map(
      unused_i => '0'
      );

  -- Control domain

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
      r.hpd <= false;
      r.configured <= false;
    end if;
  end process;

  transition: process(r, irq_n_i, aspect_i, hdmi_i, audio_enable_i, audio_rate_i,
                      access_ready_s, access_valid_s, access_error_s, access_rdata_s) is
    variable entry: byte_string(0 to 1);
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.timer <= startup_cycles_c;
        rin.state <= ST_STARTUP;

      when ST_STARTUP =>
        if r.timer /= 0 then
          rin.timer <= r.timer - 1;
        else
          rin.state <= ST_IRQ_READ;
        end if;

      when ST_IRQ_READ =>
        rin.write <= false;
        rin.addr <= reg_irq_status_c;
        rin.next_state <= ST_IRQ_CHECK;
        rin.state <= ST_ACCESS_CMD;

      when ST_IRQ_CHECK =>
        rin.hpd_event <= r.data(reg_irq_status_hpd_c) = '1';
        rin.state <= ST_IRQ_CLEAR;

      when ST_IRQ_CLEAR =>
        rin.write <= true;
        rin.addr <= reg_irq_status_c;
        rin.data <= irq_clear_c;
        rin.next_state <= ST_HPD_READ;
        rin.state <= ST_ACCESS_CMD;

      when ST_HPD_READ =>
        rin.write <= false;
        rin.addr <= reg_status_c;
        rin.next_state <= ST_HPD_CHECK;
        rin.state <= ST_ACCESS_CMD;

      when ST_HPD_CHECK =>
        rin.hpd <= r.data(reg_status_hpd_c) = '1';
        if r.data(reg_status_hpd_c) = '0' then
          rin.configured <= false;
          rin.timer <= poll_cycles_c;
          rin.state <= ST_WAIT;
        elsif r.hpd_event or not r.configured then
          rin.configured <= false;
          rin.index <= 0;
          rin.setup <= setup_t'(aspect => aspect_i,
                                hdmi => hdmi_i = '1',
                                audio_enable => audio_enable_i = '1',
                                audio_rate => audio_rate_i);
          rin.state <= ST_CONFIG;
        else
          rin.timer <= poll_cycles_c;
          rin.state <= ST_WAIT;
        end if;

      when ST_CONFIG =>
        if r.index /= config_entry_count_c then
          entry := config_entry(r.index, r.setup);
          rin.write <= true;
          rin.addr <= entry(0);
          rin.data <= entry(1);
          rin.index <= r.index + 1;
          rin.next_state <= ST_CONFIG;
          rin.state <= ST_ACCESS_CMD;
        else
          rin.configured <= true;
          rin.timer <= poll_cycles_c;
          rin.state <= ST_WAIT;
        end if;

      when ST_WAIT =>
        if irq_n_i = '0' or r.timer = 0 then
          rin.state <= ST_IRQ_READ;
        else
          rin.timer <= r.timer - 1;
        end if;

      when ST_ACCESS_CMD =>
        if access_ready_s = '1' then
          rin.state <= ST_ACCESS_RSP;
        end if;

      when ST_ACCESS_RSP =>
        if access_valid_s = '1' then
          if access_error_s = '1' then
            -- Chip did not answer, start over from a clean slate later
            rin.configured <= false;
            rin.timer <= poll_cycles_c;
            rin.state <= ST_WAIT;
          else
            if not r.write then
              rin.data <= access_rdata_s(0);
            end if;
            rin.state <= r.next_state;
          end if;
        end if;
    end case;
  end process;

  moore: process(r) is
  begin
    if r.hpd then
      hpd_o <= '1';
    else
      hpd_o <= '0';
    end if;

    if r.configured then
      ready_o <= '1';
    else
      ready_o <= '0';
    end if;

    if r.write then
      access_write_s <= '1';
    else
      access_write_s <= '0';
    end if;

    access_cmd_valid_s <= '0';
    access_rsp_ready_s <= '0';
    case r.state is
      when ST_ACCESS_CMD =>
        access_cmd_valid_s <= '1';
      when ST_ACCESS_RSP =>
        access_rsp_ready_s <= '1';
      when others =>
        null;
    end case;
  end process;

  register_access: nsl_i2c.transactor.framed_addressed_controller
    generic map(
      addr_byte_count_c => 1,
      big_endian_c => true,
      txn_byte_count_max_c => 1
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,

      cmd_i => cmd_i,
      cmd_o => cmd_o,
      rsp_o => rsp_o,
      rsp_i => rsp_i,

      valid_i => access_cmd_valid_s,
      ready_o => access_ready_s,
      saddr_i => i2c_saddr_c,
      addr_i => unsigned(r.addr),
      write_i => access_write_s,
      wdata_i(0) => r.data,
      data_byte_count_i => 1,

      valid_o => access_valid_s,
      ready_i => access_rsp_ready_s,
      rdata_o => access_rdata_s,
      error_o => access_error_s
      );

  -- Video domain

  pixel_regs: process(pixel_clock_i, pixel_reset_n_i) is
  begin
    if rising_edge(pixel_clock_i) then
      pr <= prin;
    end if;

    if pixel_reset_n_i = '0' then
      pr.h_state <= RS_ACT;
      pr.h_left <= (others => '0');
      pr.v_state <= RS_ACT;
      pr.v_left <= (others => '0');
      pr.de <= '0';
    end if;
  end process;

  pixel_transition: process(pr,
                            h_fp_m1_i, h_sync_m1_i, h_bp_m1_i, h_act_m1_i,
                            v_fp_m1_i, v_sync_m1_i, v_bp_m1_i, v_act_m1_i,
                            hsync_i, vsync_i,
                            valid_s, stream_pixel_s) is
    variable v_next: boolean;
  begin
    prin <= pr;

    v_next := false;

    case pr.h_state is
      when RS_FP =>
        if pr.h_left /= 0 then
          prin.h_left <= pr.h_left - 1;
        else
          prin.h_left <= resize(h_sync_m1_i, h_width_c);
          prin.h_state <= RS_SYNC;
          v_next := true;
        end if;

      when RS_SYNC =>
        if pr.h_left /= 0 then
          prin.h_left <= pr.h_left - 1;
        else
          prin.h_left <= resize(h_bp_m1_i, h_width_c);
          prin.h_state <= RS_BP;
        end if;

      when RS_BP =>
        if pr.h_left /= 0 then
          prin.h_left <= pr.h_left - 1;
        else
          prin.h_left <= resize(h_act_m1_i, h_width_c);
          prin.h_state <= RS_ACT;
        end if;

      when RS_ACT =>
        if pr.h_left /= 0 then
          prin.h_left <= pr.h_left - 1;
        else
          prin.h_state <= RS_FP;
          prin.h_left <= resize(h_fp_m1_i, h_width_c);
        end if;
    end case;

    if v_next then
      case pr.v_state is
        when RS_FP =>
          if pr.v_left /= 0 then
            prin.v_left <= pr.v_left - 1;
          else
            prin.v_left <= resize(v_sync_m1_i, v_width_c);
            prin.v_state <= RS_SYNC;
          end if;

        when RS_SYNC =>
          if pr.v_left /= 0 then
            prin.v_left <= pr.v_left - 1;
          else
            prin.v_left <= resize(v_bp_m1_i, v_width_c);
            prin.v_state <= RS_BP;
          end if;

        when RS_BP =>
          if pr.v_left /= 0 then
            prin.v_left <= pr.v_left - 1;
          else
            prin.v_left <= resize(v_act_m1_i, v_width_c);
            prin.v_state <= RS_ACT;
          end if;

        when RS_ACT =>
          if pr.v_left /= 0 then
            prin.v_left <= pr.v_left - 1;
          else
            prin.v_state <= RS_FP;
            prin.v_left <= resize(v_fp_m1_i, v_width_c);
          end if;
      end case;
    end if;

    if pr.h_state = RS_SYNC then
      prin.hsync <= hsync_i;
    else
      prin.hsync <= not hsync_i;
    end if;

    if pr.v_state = RS_SYNC then
      prin.vsync <= vsync_i;
    else
      prin.vsync <= not vsync_i;
    end if;

    if pr.h_state = RS_ACT and pr.v_state = RS_ACT then
      prin.de <= '1';
    else
      prin.de <= '0';
    end if;

    -- The raster cannot wait: a pixel the stream did not hold goes
    -- out black.
    if valid_s = '1' then
      prin.data <= std_ulogic_vector(stream_pixel_s(1)(7 downto 0))
                   & std_ulogic_vector(stream_pixel_s(0)(7 downto 0));
    else
      prin.data <= x"8010";
    end if;
  end process;

  ready_s <= '1' when pr.h_state = RS_ACT and pr.v_state = RS_ACT else '0';
  sof_s <= '1' when pr.h_state = RS_SYNC and pr.v_state = RS_SYNC
           and pr.h_left = 0 and pr.v_left = 0 else '0';
  sol_s <= '1' when pr.h_state = RS_SYNC and pr.v_state = RS_ACT
           and pr.h_left = 0 else '0';

  unframer: nsl_video.raster.pixel_stream_unframer
    generic map(
      config_c => config_c
      )
    port map(
      clock_i => pixel_clock_i,
      reset_n_i => pixel_reset_n_i,
      in_i => pixel_i,
      in_o => pixel_o,
      sof_i => sof_s,
      sol_i => sol_s,
      ready_i => ready_s,
      valid_o => valid_s,
      pixel_o => stream_pixel_s,
      synced_o => synced_o
      );

  de_o <= pr.de;
  hsync_o <= pr.hsync;
  vsync_o <= pr.vsync;
  data_o <= pr.data;

  -- Chip samples on its clock rising edge, forward an inverted clock
  -- to have it sample in the middle of the data eye.
  forward_s.p <= pixel_clock_i;
  forward_s.n <= not pixel_clock_i;

  clock_forward: nsl_io.ddr.ddr_output
    port map(
      clock_i => forward_s,
      d_i => "10",
      dd_o => clock_o
      );

end architecture;
