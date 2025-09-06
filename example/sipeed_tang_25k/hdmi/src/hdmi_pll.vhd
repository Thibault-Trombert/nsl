library IEEE;
use IEEE.std_logic_1164.all;


entity Hdmi_Pll is
    port (
        clkin: in std_logic;
        clkout0: out std_logic;
        clkout1: out std_logic;
        lock: out std_logic;
        mdclk: in std_logic;
        reset: in std_logic
    );
end Hdmi_Pll;


architecture Behavioral of Hdmi_Pll is
    signal mdrdo: std_logic_vector(7 downto 0);
    signal wMdOpc: std_logic_vector(1 downto 0);
    signal wMdAInc: std_logic;
    signal wMdDIn: std_logic_vector(7 downto 0);
    signal wMdQOut: std_logic_vector(7 downto 0);
    signal pll_lock: std_logic;
    signal pll_rst: std_logic;


    component Hdmi_Pll_MOD
        port (
            clkout1: out std_logic;
            clkout0: out std_logic;
            lock: out std_logic;
            reset: in std_logic;
            mdrdo: out std_logic_vector(7 downto 0);
            clkin: in std_logic;
            mdclk: in std_logic;
            mdopc: in std_logic_vector(1 downto 0);
            mdainc: in std_logic;
            mdwdi: in std_logic_vector(7 downto 0)
        );
    end component;


    component HDMI_PLL_INIT
        generic (
            CLK_PERIOD: INTEGER:= 20;
            MULTI_FAC: INTEGER:= 24
        );
        port (
            I_RST: in std_logic;
            O_RST: out std_logic;
            I_LOCK: in std_logic;
            O_LOCK: out std_logic;
            I_MD_CLK: in std_logic;
            O_MD_INC: out std_logic;
            O_MD_OPC: out std_logic_vector(1 downto 0);
            O_MD_WR_DATA: out std_logic_vector(7 downto 0);
            I_MD_RD_DATA: in std_logic_vector(7 downto 0);
            PLL_INIT_BYPASS: in std_logic;
            MDRDO: out std_logic_vector(7 downto 0);
            MDOPC: in std_logic_vector(1 downto 0);
            MDAINC: in std_logic;
            MDWDI: in std_logic_vector(7 downto 0)
        );
    end component;


begin
    u_pll: Hdmi_Pll_MOD
        port map (
            clkout1 => clkout1,
            clkout0 => clkout0,
            lock => pll_lock,
            mdrdo => wMdQOut,
            clkin => clkin,
            reset => pll_rst,
            mdclk => mdclk,
            mdopc => wMdOpc,
            mdainc => wMdAInc,
            mdwdi => wMdDIn
        );


    u_hdmi_pll_init: HDMI_PLL_INIT
        generic map (
            CLK_PERIOD => 20,
            MULTI_FAC => 33
        )
        port map (
            I_RST => reset,
            O_RST => pll_rst,
            I_LOCK => pll_lock,
            O_LOCK => lock,
            I_MD_CLK => mdclk,
            O_MD_INC => wMdAInc,
            O_MD_OPC => wMdOpc,
            O_MD_WR_DATA => wMdDIn,
            I_MD_RD_DATA => wMdQOut,
            PLL_INIT_BYPASS => '0',
            MDRDO => mdrdo,
            MDOPC => "00",
            MDAINC => '0',
            MDWDI => "00000000"
        );


end Behavioral; --Hdmi_Pll
