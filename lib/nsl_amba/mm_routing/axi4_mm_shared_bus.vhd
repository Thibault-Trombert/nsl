library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work, nsl_logic;
use work.axi4_mm.all;
use work.address.all;
use work.mm_routing.all;
use nsl_logic.bool.all;

entity axi4_mm_shared_bus is
  generic(
    config_c : config_t;
    master_count_c : positive;
    routing_table_c : work.address.address_vector;
    default_slave_c : integer := -1
    );
  port(
    clock_i : in std_ulogic;
    reset_n_i : in std_ulogic;

    slave_i : in master_vector(0 to master_count_c-1);
    slave_o : out slave_vector(0 to master_count_c-1);

    master_o : out master_vector(0 to routing_table_c'length-1);
    master_i : in slave_vector(0 to routing_table_c'length-1)
    );
end entity;

architecture beh of axi4_mm_shared_bus is

  constant external_slave_count_c : natural := routing_table_c'length;
  constant has_internal_error_slave_c : boolean := default_slave_c < 0;
  constant internal_slave_count_c : natural := external_slave_count_c + if_else(has_internal_error_slave_c, 1, 0);
  constant error_slave_index_c : natural := external_slave_count_c;
  constant actual_default_slave_c : natural := if_else(has_internal_error_slave_c, error_slave_index_c, default_slave_c);

  type state_t is (
    ST_RESET,
    ST_IDLE,
    ST_AR,
    ST_R,
    ST_AW,
    ST_W,
    ST_B
    );

  type regs_t is record
    state : state_t;
    master_idx : natural range 0 to master_count_c-1;
    slave_idx : natural range 0 to internal_slave_count_c-1;
    len_m1 : unsigned(config_c.len_width-1 downto 0);
  end record;

  signal r, rin : regs_t;

  -- Internal error slave signals
  signal error_slave_axi_o : master_t;
  signal error_slave_axi_i : slave_t;

  -- Combined slave responses (external + optional internal error slave)
  type slave_response_array_t is array (0 to internal_slave_count_c-1) of slave_t;
  signal slave_responses : slave_response_array_t;

  -- Find highest priority master with a pending request
  -- Returns the index of the winning master and whether any request is pending
  function priority_arbitrate(
    masters : master_vector;
    check_write : boolean
    ) return natural
  is
  begin
    for i in masters'range loop
      if check_write then
        if is_valid(config_c, masters(i).aw) then
          return i;
        end if;
      else
        if is_valid(config_c, masters(i).ar) then
          return i;
        end if;
      end if;
    end loop;
    return 0;
  end function;

  function has_pending_request(
    masters : master_vector;
    check_write : boolean
    ) return boolean
  is
  begin
    for i in masters'range loop
      if check_write then
        if is_valid(config_c, masters(i).aw) then
          return true;
        end if;
      else
        if is_valid(config_c, masters(i).ar) then
          return true;
        end if;
      end if;
    end loop;
    return false;
  end function;

  -- Address decode: determine target slave from address
  function address_decode(addr : work.axi4_mm.address_t) return natural
  is
  begin
    return routing_table_lookup(
      config_c.address_width,
      routing_table_c,
      work.axi4_mm.address(config_c, addr),
      actual_default_slave_c
      );
  end function;

begin

  -- Map external slave responses
  gen_external_responses: for s in 0 to external_slave_count_c-1
  generate
    slave_responses(s) <= master_i(s);
  end generate;

  -- Map internal error slave response
  gen_error_response: if has_internal_error_slave_c
  generate
    slave_responses(error_slave_index_c) <= error_slave_axi_i;
  end generate;

  regs: process(clock_i, reset_n_i) is
  begin
    if rising_edge(clock_i) then
      r <= rin;
    end if;

    if reset_n_i = '0' then
      r.state <= ST_RESET;
    end if;
  end process;

  transition: process(r, slave_i, slave_responses) is
    variable winning_master_v : natural range 0 to master_count_c-1;
    variable target_slave_v : natural range 0 to internal_slave_count_c-1;
  begin
    rin <= r;

    case r.state is
      when ST_RESET =>
        rin.state <= ST_IDLE;

      when ST_IDLE =>
        -- Priority: writes before reads, lower index before higher
        -- First check if any master has a write pending
        if has_pending_request(slave_i, true) then
          winning_master_v := priority_arbitrate(slave_i, true);
          target_slave_v := address_decode(slave_i(winning_master_v).aw);
          rin.master_idx <= winning_master_v;
          rin.slave_idx <= target_slave_v;
          rin.state <= ST_AW;
        elsif has_pending_request(slave_i, false) then
          winning_master_v := priority_arbitrate(slave_i, false);
          target_slave_v := address_decode(slave_i(winning_master_v).ar);
          rin.master_idx <= winning_master_v;
          rin.slave_idx <= target_slave_v;
          rin.len_m1 <= length_m1(config_c, slave_i(winning_master_v).ar, config_c.len_width);
          rin.state <= ST_AR;
        end if;

      when ST_AR =>
        -- Wait for slave to accept AR
        if is_ready(config_c, slave_responses(r.slave_idx).ar) then
          rin.state <= ST_R;
        end if;

      when ST_R =>
        -- Forward R beats until last
        if is_valid(config_c, slave_responses(r.slave_idx).r) and
           is_ready(config_c, slave_i(r.master_idx).r) then
          if is_last(config_c, slave_responses(r.slave_idx).r) then
            rin.state <= ST_IDLE;
          end if;
        end if;

      when ST_AW =>
        -- Wait for slave to accept AW
        if is_ready(config_c, slave_responses(r.slave_idx).aw) then
          rin.state <= ST_W;
        end if;

      when ST_W =>
        -- Forward W beats until last
        if is_valid(config_c, slave_i(r.master_idx).w) and
           is_ready(config_c, slave_responses(r.slave_idx).w) then
          if is_last(config_c, slave_i(r.master_idx).w) then
            rin.state <= ST_B;
          end if;
        end if;

      when ST_B =>
        -- Wait for B response and master to accept it
        if is_valid(config_c, slave_responses(r.slave_idx).b) and
           is_ready(config_c, slave_i(r.master_idx).b) then
          rin.state <= ST_IDLE;
        end if;
    end case;
  end process;

  outputs: process(r, slave_i, slave_responses)
  begin
    -- Default: all outputs idle
    for m in 0 to master_count_c-1
    loop
      slave_o(m).aw <= handshake_defaults(config_c);
      slave_o(m).w <= handshake_defaults(config_c);
      slave_o(m).ar <= handshake_defaults(config_c);
      slave_o(m).b <= write_response_defaults(config_c);
      slave_o(m).r <= read_data_defaults(config_c);
    end loop;

    for s in 0 to external_slave_count_c-1
    loop
      master_o(s).aw <= address_defaults(config_c);
      master_o(s).w <= write_data_defaults(config_c);
      master_o(s).ar <= address_defaults(config_c);
      master_o(s).b <= handshake_defaults(config_c);
      master_o(s).r <= handshake_defaults(config_c);
    end loop;

    error_slave_axi_o.aw <= address_defaults(config_c);
    error_slave_axi_o.w <= write_data_defaults(config_c);
    error_slave_axi_o.ar <= address_defaults(config_c);
    error_slave_axi_o.b <= handshake_defaults(config_c);
    error_slave_axi_o.r <= handshake_defaults(config_c);

    case r.state is
      when ST_RESET | ST_IDLE =>
        null;

      when ST_AR =>
        -- Forward AR from selected master to selected slave
        if r.slave_idx < external_slave_count_c then
          master_o(r.slave_idx).ar <= slave_i(r.master_idx).ar;
        else
          error_slave_axi_o.ar <= slave_i(r.master_idx).ar;
        end if;
        -- Forward ready back to master
        slave_o(r.master_idx).ar <= slave_responses(r.slave_idx).ar;

      when ST_R =>
        -- Forward R from selected slave to selected master
        slave_o(r.master_idx).r <= slave_responses(r.slave_idx).r;
        -- Forward ready back to slave
        if r.slave_idx < external_slave_count_c then
          master_o(r.slave_idx).r <= slave_i(r.master_idx).r;
        else
          error_slave_axi_o.r <= slave_i(r.master_idx).r;
        end if;

      when ST_AW =>
        -- Forward AW from selected master to selected slave
        if r.slave_idx < external_slave_count_c then
          master_o(r.slave_idx).aw <= slave_i(r.master_idx).aw;
        else
          error_slave_axi_o.aw <= slave_i(r.master_idx).aw;
        end if;
        -- Forward ready back to master
        slave_o(r.master_idx).aw <= slave_responses(r.slave_idx).aw;

      when ST_W =>
        -- Forward W from selected master to selected slave
        if r.slave_idx < external_slave_count_c then
          master_o(r.slave_idx).w <= slave_i(r.master_idx).w;
        else
          error_slave_axi_o.w <= slave_i(r.master_idx).w;
        end if;
        -- Forward ready back to master
        slave_o(r.master_idx).w <= slave_responses(r.slave_idx).w;

      when ST_B =>
        -- Forward B from selected slave to selected master
        slave_o(r.master_idx).b <= slave_responses(r.slave_idx).b;
        -- Forward ready back to slave
        if r.slave_idx < external_slave_count_c then
          master_o(r.slave_idx).b <= slave_i(r.master_idx).b;
        else
          error_slave_axi_o.b <= slave_i(r.master_idx).b;
        end if;
    end case;
  end process;

  -- Internal error slave generation (conditional)
  gen_error_slave: if has_internal_error_slave_c
  generate
    error_slave_inst: work.mm_routing.axi4_mm_error_slave
      generic map(
        config_c => config_c
        )
      port map(
        clock_i => clock_i,
        reset_n_i => reset_n_i,
        axi_i => error_slave_axi_o,
        axi_o => error_slave_axi_i
        );
  end generate;

  -- Tie off error slave signals when not used
  gen_no_error_slave: if not has_internal_error_slave_c
  generate
    error_slave_axi_i.aw <= handshake_defaults(config_c);
    error_slave_axi_i.w <= handshake_defaults(config_c);
    error_slave_axi_i.ar <= handshake_defaults(config_c);
    error_slave_axi_i.b <= write_response_defaults(config_c);
    error_slave_axi_i.r <= read_data_defaults(config_c);
  end generate;

end architecture;
