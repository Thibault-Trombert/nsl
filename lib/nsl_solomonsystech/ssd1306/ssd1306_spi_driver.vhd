library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_spi, nsl_data, nsl_video;
use work.ssd1306.all;
use nsl_data.bytestream.all;

entity ssd1306_spi_driver is
  generic(
    clock_i_hz_c : natural;
    config_c : nsl_video.pixel_stream.config_t;
    spi_hz_c : natural := 10_000_000;

    width_c : positive range 1 to max_width_c := 128;
    height_c : positive range page_height_c to max_height_c := 64;
    column_offset_c : natural range 0 to max_width_c - 1 := 0;
    com_alternative_c : boolean := true;
    charge_pump_c : boolean := true;
    rotate_180_c : boolean := false;
    contrast_c : byte := x"8f"
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    enable_i : in std_ulogic := '1';
    refresh_i : in std_ulogic := '1';

    spi_o : out nsl_spi.spi.spi_slave_i;
    dc_o : out std_ulogic;
    reset_n_o : out std_ulogic;
    vcc_en_o : out std_ulogic;
    power_en_o : out std_ulogic;

    pixel_i : in nsl_video.pixel_stream.master_t;
    pixel_o : out nsl_video.pixel_stream.slave_t;

    synced_o : out std_ulogic
    );
end entity;

architecture beh of ssd1306_spi_driver is

  -- Serial interface timing requires tcycle >= 100ns, tclkl/tclkh >=
  -- 20ns.
  constant half_bit_cycles_c : natural :=
    (clock_i_hz_c + 2 * spi_hz_c - 1) / (2 * spi_hz_c);

  -- Reset pulse and reset-to-init delays, 3us minimum, use 10us
  constant reset_cycles_c : natural := (clock_i_hz_c + 99_999) / 100_000;
  -- Logic supply settling, 5ms
  constant power_settle_cycles_c : natural := clock_i_hz_c / 200;
  -- Panel supply settling before display on, and discharge after
  -- display off, 100ms
  constant vcc_settle_cycles_c : natural := clock_i_hz_c / 10;
  constant timer_max_c : natural := vcc_settle_cycles_c;

  constant page_count_c : natural := height_c / page_height_c;

  constant init_c : byte_string(0 to init_sequence_length_c - 1)
    := init_sequence(height => height_c,
                     com_alternative => com_alternative_c,
                     charge_pump => charge_pump_c,
                     rotate_180 => rotate_180_c,
                     contrast => contrast_c);

  constant frame_setup_c : byte_string(0 to 5) :=
    byte_string'(0 => cmd_column_address)
    & to_byte(column_offset_c)
    & to_byte(column_offset_c + width_c - 1)
    & cmd_page_address
    & to_byte(0)
    & to_byte(page_count_c - 1);

  -- Eight lines worth of pixels, one byte per column, as the panel
  -- takes them.  Buffer is a ring that rotates by one column for every
  -- pixel taken and every byte sent: the column being worked on is
  -- always at index 0, and a full turn brings column 0 back there.
  type column_vector is array (natural range 0 to width_c - 1) of byte;

  type state_t is (
    ST_OFF,
    ST_POWER_SETTLE,
    ST_RESET,
    ST_RESET_SETTLE,
    ST_INIT,
    ST_SOF,
    ST_SETUP,
    ST_SOL,
    ST_PIXEL,
    ST_PAGE_OUT,
    ST_VCC_SETTLE,
    ST_DISPLAY_ON,
    ST_IDLE,
    ST_DISPLAY_OFF,
    ST_VCC_OFF
    );

  type regs_t is
  record
    state: state_t;
    timer: natural range 0 to timer_max_c;
    ptr: natural range 0 to init_sequence_length_c;
    x: natural range 0 to width_c - 1;
    line: natural range 0 to page_height_c - 1;
    page: natural range 0 to page_count_c - 1;
    display_on: boolean;
    vcc_on: boolean;

    columns: column_vector;

    shreg: byte;
    bits_left: natural range 0 to 8;
    div: natural range 0 to half_bit_cycles_c - 1;
    sck: std_ulogic;
    dc: std_ulogic;
  end record;

  signal r, rin: regs_t;

  signal sof_s, sol_s, ready_s, valid_s: std_ulogic;
  signal stream_pixel_s: nsl_video.pixel_stream.pixel_t;

begin

  assert height_c mod page_height_c = 0
    report "Panel height must be a multiple of page height"
    severity failure;

  assert column_offset_c + width_c <= max_width_c
    report "Panel columns do not fit in controller"
    severity failure;

  assert config_c.component_count = 1
    report "Driver takes one component per pixel"
    severity failure;

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_OFF;
      r.timer <= 0;
      r.display_on <= false;
      r.vcc_on <= false;
      r.bits_left <= 0;
      r.sck <= '0';
      r.dc <= '0';
    end if;
  end process;

  transition: process(r, enable_i, refresh_i, valid_s, stream_pixel_s) is
    variable column: byte;
  begin
    rin <= r;

    if r.bits_left /= 0 then
      -- Mode-0 serializer, data shifted on falling edge, sampled by
      -- panel on rising edge.  State logic below is suspended until
      -- current byte is fully shifted out.
      if r.div /= 0 then
        rin.div <= r.div - 1;
      elsif r.sck = '0' then
        rin.sck <= '1';
        rin.div <= half_bit_cycles_c - 1;
      else
        rin.sck <= '0';
        rin.div <= half_bit_cycles_c - 1;
        rin.shreg <= r.shreg(6 downto 0) & '0';
        rin.bits_left <= r.bits_left - 1;
      end if;
    else
      case r.state is
        when ST_OFF =>
          if enable_i = '1' then
            rin.timer <= power_settle_cycles_c;
            rin.state <= ST_POWER_SETTLE;
          end if;

        when ST_POWER_SETTLE =>
          if r.timer /= 0 then
            rin.timer <= r.timer - 1;
          else
            rin.timer <= reset_cycles_c;
            rin.state <= ST_RESET;
          end if;

        when ST_RESET =>
          if r.timer /= 0 then
            rin.timer <= r.timer - 1;
          else
            rin.timer <= reset_cycles_c;
            rin.state <= ST_RESET_SETTLE;
          end if;

        when ST_RESET_SETTLE =>
          if r.timer /= 0 then
            rin.timer <= r.timer - 1;
          else
            rin.ptr <= 0;
            rin.state <= ST_INIT;
          end if;

        when ST_INIT =>
          if r.ptr /= init_c'length then
            rin.shreg <= init_c(r.ptr);
            rin.bits_left <= 8;
            rin.div <= half_bit_cycles_c - 1;
            rin.dc <= '0';
            rin.ptr <= r.ptr + 1;
          else
            rin.state <= ST_SOF;
          end if;

        when ST_SOF =>
          rin.ptr <= 0;
          rin.state <= ST_SETUP;

        when ST_SETUP =>
          if r.ptr /= frame_setup_c'length then
            rin.shreg <= frame_setup_c(r.ptr);
            rin.bits_left <= 8;
            rin.div <= half_bit_cycles_c - 1;
            rin.dc <= '0';
            rin.ptr <= r.ptr + 1;
          else
            rin.line <= 0;
            rin.page <= 0;
            rin.state <= ST_SOL;
          end if;

        when ST_SOL =>
          rin.x <= 0;
          rin.state <= ST_PIXEL;

        when ST_PIXEL =>
          if valid_s = '1' then
            column := r.columns(0);
            column(r.line) := stream_pixel_s(0)(config_c.component_bits - 1);
            rin.columns <= r.columns(1 to width_c - 1) & column;

            if r.x /= width_c - 1 then
              rin.x <= r.x + 1;
            elsif r.line /= page_height_c - 1 then
              rin.line <= r.line + 1;
              rin.state <= ST_SOL;
            else
              rin.x <= 0;
              rin.state <= ST_PAGE_OUT;
            end if;
          end if;

        when ST_PAGE_OUT =>
          rin.shreg <= r.columns(0);
          rin.bits_left <= 8;
          rin.div <= half_bit_cycles_c - 1;
          rin.dc <= '1';
          rin.columns <= r.columns(1 to width_c - 1) & r.columns(0);

          if r.x /= width_c - 1 then
            rin.x <= r.x + 1;
          elsif r.page /= page_count_c - 1 then
            rin.page <= r.page + 1;
            rin.line <= 0;
            rin.state <= ST_SOL;
          elsif not r.display_on then
            rin.vcc_on <= true;
            rin.timer <= vcc_settle_cycles_c;
            rin.state <= ST_VCC_SETTLE;
          else
            rin.state <= ST_IDLE;
          end if;

        when ST_VCC_SETTLE =>
          if r.timer /= 0 then
            rin.timer <= r.timer - 1;
          else
            rin.state <= ST_DISPLAY_ON;
          end if;

        when ST_DISPLAY_ON =>
          rin.shreg <= cmd_display_on;
          rin.bits_left <= 8;
          rin.div <= half_bit_cycles_c - 1;
          rin.dc <= '0';
          rin.display_on <= true;
          rin.state <= ST_IDLE;

        when ST_IDLE =>
          if enable_i = '0' then
            rin.state <= ST_DISPLAY_OFF;
          elsif refresh_i = '1' then
            rin.state <= ST_SOF;
          end if;

        when ST_DISPLAY_OFF =>
          rin.shreg <= cmd_display_sleep;
          rin.bits_left <= 8;
          rin.div <= half_bit_cycles_c - 1;
          rin.dc <= '0';
          rin.display_on <= false;
          rin.state <= ST_VCC_OFF;
          rin.timer <= vcc_settle_cycles_c;

        when ST_VCC_OFF =>
          -- Only reached once display-off command is fully shifted
          rin.vcc_on <= false;
          if r.timer /= 0 then
            rin.timer <= r.timer - 1;
          else
            rin.state <= ST_OFF;
          end if;
      end case;
    end if;
  end process;

  moore: process(r) is
  begin
    spi_o.sck <= r.sck;
    spi_o.mosi <= r.shreg(7);
    dc_o <= r.dc;

    sof_s <= '0';
    sol_s <= '0';
    ready_s <= '0';

    case r.state is
      when ST_INIT | ST_SOF | ST_SETUP | ST_SOL | ST_PIXEL | ST_PAGE_OUT
        | ST_DISPLAY_ON | ST_DISPLAY_OFF =>
        spi_o.cs_n <= '0';
      when others =>
        if r.bits_left /= 0 then
          spi_o.cs_n <= '0';
        else
          spi_o.cs_n <= '1';
        end if;
    end case;

    case r.state is
      when ST_OFF =>
        power_en_o <= '0';
      when others =>
        power_en_o <= '1';
    end case;

    case r.state is
      when ST_OFF | ST_POWER_SETTLE | ST_RESET =>
        reset_n_o <= '0';
      when others =>
        reset_n_o <= '1';
    end case;

    if r.vcc_on then
      vcc_en_o <= '1';
    else
      vcc_en_o <= '0';
    end if;

    if r.bits_left = 0 then
      case r.state is
        when ST_SOF =>
          sof_s <= '1';
        when ST_SOL =>
          sol_s <= '1';
        when ST_PIXEL =>
          ready_s <= '1';
        when others =>
          null;
      end case;
    end if;
  end process;

  -- The panel scan holds its serial interface when the stream has no
  -- pixel, so a late pixel costs time, not position.
  unframer: nsl_video.raster.pixel_stream_unframer
    generic map(
      config_c => config_c,
      raster_can_wait_c => true
      )
    port map(
      clock_i => clock_i,
      reset_n_i => reset_n_i,
      in_i => pixel_i,
      in_o => pixel_o,
      sof_i => sof_s,
      sol_i => sol_s,
      ready_i => ready_s,
      valid_o => valid_s,
      pixel_o => stream_pixel_s,
      synced_o => synced_o
      );

end architecture;
