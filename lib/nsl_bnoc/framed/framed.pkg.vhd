library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library nsl_math;

package framed is

  subtype framed_data_t is std_ulogic_vector(7 downto 0);

  type framed_req is record
    data : framed_data_t;
    last : std_ulogic;
    valid  : std_ulogic;
  end record;

  type framed_ack is record
    ready  : std_ulogic;
  end record;

  type framed_bus is record
    req: framed_req;
    ack: framed_ack;
  end record;

  type framed_req_array is array(natural range <>) of framed_req;
  type framed_ack_array is array(natural range <>) of framed_ack;
  type framed_bus_array is array(natural range <>) of framed_bus;

  component framed_fifo is
    generic(
      depth      : natural;
      clk_count  : natural range 1 to 2
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic_vector(0 to clk_count-1);

      p_in_val   : in framed_req;
      p_in_ack   : out framed_ack;

      p_out_val   : out framed_req;
      p_out_ack   : in framed_ack
      );
  end component;

  component framed_fifo_slice is
    port(
      reset_n_i  : in  std_ulogic;
      clock_i    : in  std_ulogic;

      in_i   : in framed_req;
      in_o   : out framed_ack;

      out_o   : out framed_req;
      out_i   : in framed_ack
      );
  end component;

  component framed_fifo_atomic is
    generic(
      depth : natural;
      txn_depth : natural := 4;
      clk_count  : natural range 1 to 2
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic_vector(0 to clk_count-1);

      p_in_val   : in framed_req;
      p_in_ack   : out framed_ack;

      p_out_val   : out framed_req;
      p_out_ack   : in framed_ack
      );
  end component;

  component framed_arbitrer is
    generic(
      source_count : natural
      );
    port(
      p_resetn   : in  std_ulogic;
      p_clk      : in  std_ulogic;

      p_selected : out unsigned(nsl_math.arith.log2(source_count)-1 downto 0);
      
      p_cmd_val   : in framed_req_array(0 to source_count - 1);
      p_cmd_ack   : out framed_ack_array(0 to source_count - 1);
      p_rsp_val   : out framed_req_array(0 to source_count - 1);
      p_rsp_ack   : in framed_ack_array(0 to source_count - 1);

      p_target_cmd_val   : out framed_req;
      p_target_cmd_ack   : in framed_ack;
      p_target_rsp_val   : in framed_req;
      p_target_rsp_ack   : out framed_ack
      );
  end component;

  component framed_gate is
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      enable_i   : in std_ulogic;

      in_i   : in framed_req;
      in_o   : out framed_ack;
      out_o   : out framed_req;
      out_i   : in framed_ack
      );
  end component;

  -- This component creates a framed context from a fifo + flush
  -- operation.
  --
  -- Flush lags one cycle after matching data cycle,
  -- whatever the data flowing through during this later cycle.
  --
  -- This creates three frames containing data [0, 1, 2] on the output:
  --            _   _   _   _   _   _   _   _   _   _   _   _   _   _
  -- clock_i \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \_/ \
  --         _______________________________________________
  -- ready_o                                                \_________
  --             ___________         _______________________     _____
  -- valid_i ___/           \_______/                       \___/
  -- data_i  ---X 0 X 1 X 2 X-------X 0 X 1 X 2 X 0 X 1 X 2 X---X 8 X
  --                             ___             ___             ___
  -- flush_i ___________________/   \___________/   \___________/   \_
  --
  component framed_committer is
    port(
      reset_n_i   : in  std_ulogic;
      clock_i     : in  std_ulogic;

      data_i : in framed_data_t;
      valid_i : in std_ulogic;
      ready_o : out std_ulogic;

      flush_i : in std_ulogic;

      req_o : out framed_req;
      ack_i : in framed_ack
      );
  end component;

end package framed;
