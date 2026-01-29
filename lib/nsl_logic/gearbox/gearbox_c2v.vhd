library ieee;
use ieee.std_logic_1164.all;

-- Constant-to-variable width gearbox (pipelined)
--
-- Pipeline stages:
--   Stage 1: Register input data when ready
--   Stage 2: Shift input to correct position based on fill count
--   Stage 3: Merge shifted data into buffer, shift out by out_len_i
--
-- Latency: 2 cycles from input to output
-- Buffer size: 2 * output_max_width_c + input_width_c

entity gearbox_c2v is
  generic(
    input_width_c      : positive;
    output_max_width_c : positive
    );
  port(
    clock_i    : in  std_ulogic;
    reset_n_i  : in  std_ulogic;

    in_i       : in  std_ulogic_vector(0 to input_width_c - 1);
    in_ready_o : out std_ulogic;

    out_len_i  : in  integer range 0 to output_max_width_c;
    out_o      : out std_ulogic_vector(0 to output_max_width_c - 1)
    );
end entity;

architecture rtl of gearbox_c2v is

  constant ready_threshold_c : natural := 2 * output_max_width_c;
  constant buffer_size_c : natural := ready_threshold_c + input_width_c;

  subtype fill_t is integer range 0 to buffer_size_c;

  type regs_t is record
    -- Stage 1: registered input
    s1_data  : std_ulogic_vector(0 to input_width_c - 1);
    s1_valid : std_ulogic;

    -- Stage 2: shifted input (positioned for merge)
    s2_data  : std_ulogic_vector(0 to buffer_size_c - 1);
    s2_valid : std_ulogic;

    -- Buffer state
    buffer_bits : std_ulogic_vector(0 to buffer_size_c - 1);
    fill        : fill_t;
  end record;

  signal r, rin : regs_t;
  signal merged_s : std_ulogic_vector(0 to buffer_size_c - 1);

begin

  assert input_width_c >= output_max_width_c
    report "gearbox_c2v: input_width_c must be >= output_max_width_c"
    severity failure;

  merged_s <= r.buffer_bits or r.s2_data;

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.s1_valid <= '0';
      r.s2_valid <= '0';
      r.fill <= 0;
    end if;
  end process;

  transition: process(r, in_i, out_len_i) is
    variable v_fill_after_merge : integer range 0 to buffer_size_c;
    variable v_consume          : integer range 0 to output_max_width_c;
    variable v_new_fill         : fill_t;
    variable v_shift_amount     : integer range 0 to buffer_size_c;
    variable v_shifted          : std_ulogic_vector(0 to buffer_size_c - 1);
    variable v_merged           : std_ulogic_vector(0 to buffer_size_c - 1);
    variable v_ready            : boolean;
    variable v_s2_len           : integer range 0 to input_width_c;
  begin
    -- Compute s2 contribution
    if r.s2_valid = '1' then
      v_s2_len := input_width_c;
    else
      v_s2_len := 0;
    end if;

    -- Compute fill after merging s2
    v_fill_after_merge := r.fill + v_s2_len;

    -- Limit consumption to available bits (prevents underflow during warmup)
    if v_fill_after_merge >= out_len_i then
      v_consume := out_len_i;
    else
      v_consume := v_fill_after_merge;
    end if;

    -- Compute new fill after output consumption
    v_new_fill := v_fill_after_merge - v_consume;

    -- Compute shift amount for s1 (where data should go after this cycle's operations)
    v_shift_amount := v_new_fill;

    -- Stage 2: Shift s1 data to correct position
    v_shifted := (others => '0');
    if r.s1_valid = '1' then
      for shift in 0 to buffer_size_c - 1 loop
        if v_shift_amount = shift then
          for i in 0 to input_width_c - 1 loop
            v_shifted(shift + i) := r.s1_data(i);
          end loop;
        end if;
      end loop;
    end if;

    -- Stage 3: Merge s2 into buffer
    v_merged := r.buffer_bits or r.s2_data;

    -- Apply output consumption (shift left by v_consume)
    for shift in 1 to output_max_width_c loop
      if v_consume = shift then
        for i in 0 to buffer_size_c - shift - 1 loop
          rin.buffer_bits(i) <= v_merged(i + shift);
        end loop;
        for i in buffer_size_c - shift to buffer_size_c - 1 loop
          rin.buffer_bits(i) <= '0';
        end loop;
      end if;
    end loop;
    if v_consume = 0 then
      rin.buffer_bits <= v_merged;
    end if;

    rin.fill <= v_new_fill;

    -- Update s2 pipeline stage
    rin.s2_data <= v_shifted;
    rin.s2_valid <= r.s1_valid;

    -- Stage 1: Capture input if ready
    -- Ready when we have room for new input after accounting for in-flight data
    -- In-flight: s1 (if valid) will become s2, current s2 will be merged
    -- After this cycle: new_fill + (input_width if s1_valid)
    if r.s1_valid = '1' then
      v_ready := v_new_fill + input_width_c <= ready_threshold_c;
    else
      v_ready := v_new_fill <= ready_threshold_c;
    end if;

    if v_ready then
      rin.s1_data <= in_i;
      rin.s1_valid <= '1';
    else
      rin.s1_valid <= '0';
    end if;

    if v_ready then
      in_ready_o <= '1';
    else
      in_ready_o <= '0';
    end if;
  end process;

  -- Output is the first output_max_width_c bits after merging
  out_o <= merged_s(0 to output_max_width_c - 1);

end architecture;
