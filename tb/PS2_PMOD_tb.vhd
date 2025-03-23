library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use ieee.std_logic_unsigned.all;

entity PS2_PMOD_tb is
end PS2_PMOD_tb;

architecture Behavioral of PS2_PMOD_tb is
--komendy wysyłane/odbierane
    constant reset_mouse: std_logic_vector(7 downto 0) := X"FF";
    constant enable_data_reporting : std_logic_vector (7 downto 0) := X"F4";
    constant self_test_passed : std_logic_vector (7 downto 0) := X"AA";
    constant self_test_passed_parity : std_logic := '0';
    constant device_id : std_logic_vector (7 downto 0) := X"00";
    constant device_id_parity : std_logic := '0';
    constant acknowledge : std_logic_vector (7 downto 0) := X"FA";
    constant acknowledge_parity : std_logic := '1';
    type std_logic_matrix is array (natural range <>) of std_logic_vector(7 downto 0);

    constant data_reporting_byte0: std_logic_matrix(0 to 4) := (
    X"38",--znak x+ i y+ przyciski nie wciśnięte  
    X"18",--znak x+ i y- przyciski nie wciśnięte  
    X"28",--znak x- i y+ przyciski nie wciśnięte  
    X"39",--znak x+ i y+ przycisk lewy wciśnięty  
    X"3A" --znak x+ i y+ przycisk prawy wciśnięty  
    );
    --bajt 1 stany przycisków i informacje o przesunięciu
    constant data_reporting_byte0_parity : std_logic_vector := (
        '0',
        '1',
        '1',
        '1',
        '1');
    --bajt 2 przesunięcie x
    constant data_reporting_byte1: std_logic_matrix(0 to 4) := (
        X"20",  
        X"40",  
        X"80",  
        X"82",  
        X"3c"   
    );
    --bajt 3 przesunięcie y
    constant data_reporting_byte1_parity : std_logic_vector := (
        '0',
        '0',
        '0',
        '1',
        '1');

    constant data_reporting_byte2: std_logic_matrix(0 to 4) := (
        X"00",  
        X"42",  
        X"82",  
        X"84",  
        X"3f"   
    );

    constant data_reporting_byte2_parity : std_logic_vector := (
        '0',
        '0',
        '0',
        '1',
        '1');

        signal data_byte_index : natural range 0 to 4:=0;

    -- Deklaracja sygnałów 
    signal ps2_clk_tb  : std_logic:='Z';       
    signal ps2_data_tb : std_logic:='Z';       
    signal reset_tb    : std_logic:='0';
    signal y_axis_position_tb  : std_logic_vector(9 downto 0):= (others => '0');
    signal x_axis_position_tb  : std_logic_vector(8 downto 0):= (others => '0');
    signal left_button_state_tb : std_logic:= '0';
    signal middle_button_state_tb : std_logic:= '0';
    signal right_button_state_tb : std_logic:= '0';
    signal data_clk_counter : natural range 0 to 15 := 0;
    signal request_to_send_detected: std_logic:='0';
    signal counter100us: std_logic_vector(15 downto 0):= (others => '0');
    signal received_data  : std_logic_vector(7 downto 0):= (others => '0');
    signal data_frame_complete: std_logic:='0';
    signal transfer_mode :std_logic:='0';--0-receive,1-transmit
    signal data_frame_tb: std_logic_vector (10 downto 0) :='1' & self_test_passed_parity & self_test_passed &'0';
    signal reset_sequence_response_sent: std_logic:='0';
    signal detected_enable_data_reporting_request: std_logic:='0';
    signal received_tb :std_logic_vector(7 downto 0):= (others => '0');
    type fsm_state is (
    wait_for_reset,send_self_test_passed_and_id,wait_for_streaming_mode_command,streaming_mode
    );

    signal state : fsm_state :=wait_for_reset;
    
    component PS2_PMOD
        port(
            ps2_clk  : inout std_logic;
            ps2_data : inout std_logic;
            reset    : in std_logic;
            clock    : in std_logic; --clock 50MHz
            y_axis_position  : out std_logic_vector(9 downto 0);
            x_axis_position  : out std_logic_vector(8 downto 0);
            left_button_state: out std_logic;
            middle_button_state: out std_logic;
            right_button_state: out std_logic;
            received : out std_logic_vector(7 downto 0)
    
        );
    end component;



    constant CLK_PERIOD : time := 20 ns; -- zegar 50 MHz (T=20 ns)
    signal clk_gen      : std_logic := '0';
    constant DATA_CLK_PERIOD : time := 62500 ns; -- zegar 16kHZ (T=62,5 us)


begin

    -- Instancja modułu
    uut: PS2_PMOD
        port map(
            ps2_clk  => ps2_clk_tb,
            ps2_data => ps2_data_tb,
            reset    => reset_tb,
            clock    => clk_gen,
            x_axis_position  => x_axis_position_tb,
            y_axis_position  => y_axis_position_tb,
            left_button_state => left_button_state_tb,
            middle_button_state => middle_button_state_tb,
            right_button_state => right_button_state_tb,
            received => received_tb
        );

    --generacja zegara 50 MHz 
    process is
    begin

        clk_gen <= '0';
        wait for CLK_PERIOD / 2;
        clk_gen <= '1';
        wait for CLK_PERIOD / 2;

    end process;

    fsm_process: process(clk_gen)
    begin
        if rising_edge(clk_gen) then
        --transfer mode 0-receive,1-transmit
            case state is
                when wait_for_reset=>
                    transfer_mode <='0';
                    if(data_frame_complete = '1')then
                        state <=send_self_test_passed_and_id;
                    end if;
                when send_self_test_passed_and_id=>
                    transfer_mode <='1';
                    if(reset_sequence_response_sent = '1')then
                        state <= wait_for_streaming_mode_command;
                    end if;
                when wait_for_streaming_mode_command=>
                    transfer_mode <= '0';
                    if(detected_enable_data_reporting_request = '1')
                    then
                        state <= streaming_mode;
                        transfer_mode <='1';
                    end if;
                when streaming_mode=>
                    transfer_mode <='1';
            end case;

        end if;
    end process;


    --ten proces dostarcza do modułu ps2 zegar i dane, lub odbiera dane od modułu w zależności od trybu transfer_mode
    --najpierw symulowany jest reset myszki i wprowadzenie w tryb raportowania, a potem nadawanie pakietów danych przez mysz
    generate_clk_host_to_device : process is
    begin
    if(transfer_mode = '0') then
        if (request_to_send_detected = '1' and data_clk_counter <= 9 and data_frame_complete = '0' )
            then
                ps2_clk_tb <= '1';
                wait for DATA_CLK_PERIOD/2;
                ps2_clk_tb <= '0';
                wait for DATA_CLK_PERIOD/2;
        elsif(request_to_send_detected = '1' and data_clk_counter > 9)
            then
                ps2_clk_tb <= '1';
                wait for DATA_CLK_PERIOD/2;
                ps2_clk_tb <= '0';
                ps2_data_tb <='0';
                wait for DATA_CLK_PERIOD/2;
                ps2_clk_tb <= '1';
                wait for DATA_CLK_PERIOD/2;
                ps2_data_tb <='1';
                wait for 10us;
                if(received_data = enable_data_reporting)
                then
                    detected_enable_data_reporting_request <= '1';
                end if;
            end if;

    else

            if (data_frame_complete = '1'  and reset_sequence_response_sent = '0')
            then
            wait for 10us;
            for i in 1 to 11 loop
                    ps2_clk_tb <= '1';
                    ps2_data_tb <= data_frame_tb(i-1);
                    wait for DATA_CLK_PERIOD/2;
                    ps2_clk_tb <= '0';
                    wait for DATA_CLK_PERIOD/2;
                end loop;
                ps2_clk_tb <= '1';
            wait for 15us;
            data_frame_tb<= '1'& device_id_parity & device_id &'0';
            wait for 100ns;
           for i in 1 to 11 loop
                   ps2_clk_tb <= '1';
                   ps2_data_tb <= data_frame_tb(i-1);

                   wait for DATA_CLK_PERIOD/2;
                   ps2_clk_tb <= '0'; 
                   wait for DATA_CLK_PERIOD/2;

               end loop;
               ps2_clk_tb <= '1';
               ps2_data_tb <= '1';
               reset_sequence_response_sent <= '1';
            wait for CLK_PERIOD;
            ps2_clk_tb <= 'Z';
            ps2_data_tb <= 'Z';

            end if;
            if(data_frame_complete = '1' and detected_enable_data_reporting_request = '1')  
            then
            data_frame_tb<= '1' & acknowledge_parity & acknowledge &'0';
                 wait for 10us;
            for i in 1 to 11 loop
                    ps2_clk_tb <= '1';
                    ps2_data_tb <= data_frame_tb(i-1);
                    wait for DATA_CLK_PERIOD/2;
                    ps2_clk_tb <= '0';
                    wait for DATA_CLK_PERIOD/2;
                end loop;
                ps2_clk_tb <= '1';
            wait for 200ms;
            data_frame_tb<= '1' & data_reporting_byte0_parity(data_byte_index) & data_reporting_byte0(data_byte_index) &'0';
                 wait for 10us;
            for i in 1 to 11 loop
                    ps2_clk_tb <= '1';
                    ps2_data_tb <= data_frame_tb(i-1);
                    wait for DATA_CLK_PERIOD/2;
                    ps2_clk_tb <= '0';
                    wait for DATA_CLK_PERIOD/2;
                end loop;
                ps2_clk_tb <= '1';
            wait for 15us;
            data_frame_tb<= '1' & data_reporting_byte1_parity(data_byte_index) & data_reporting_byte1(data_byte_index) &'0';
            wait for 100ns;
           for i in 1 to 11 loop
                   ps2_clk_tb <= '1';
                   ps2_data_tb <= data_frame_tb(i-1);

                   wait for DATA_CLK_PERIOD/2;
                   ps2_clk_tb <= '0'; 
                   wait for DATA_CLK_PERIOD/2;

               end loop;
               ps2_clk_tb <= '1';
               ps2_data_tb <= '1';
               wait for 15us;
               data_frame_tb<= '1' & data_reporting_byte2_parity(data_byte_index) & data_reporting_byte2(data_byte_index) &'0';
               wait for 100ns;
                for i in 1 to 11 loop
                   ps2_clk_tb <= '1';
                   ps2_data_tb <= data_frame_tb(i-1);

                   wait for DATA_CLK_PERIOD/2;
                   ps2_clk_tb <= '0'; 
                   wait for DATA_CLK_PERIOD/2;

               end loop;
               if(data_byte_index <4)
               then
               data_byte_index <= data_byte_index +1;
               else
               data_byte_index <= natural(0);
               end if;
               ps2_clk_tb <= '1';
               ps2_data_tb <= '1';

            end if; 
    end if;
    wait for 1 ns;
    end process;
    --aby zainicjować transakcję, kontroler musi ściągnąć linię danych w dół na min. 100us
    --ten proces tego pilnuje
    detect_request_to_send : process(clk_gen)
    begin
    if rising_edge(clk_gen)
    then
        if(ps2_clk_tb='0' and request_to_send_detected='0' and data_frame_complete = '0')
        then
            if(counter100us <5000)
            then
                counter100us <= counter100us +1;
            end if;
        end if;
        if(counter100us >=5000 and request_to_send_detected = '0' and ps2_clk_tb='Z') then
            
                counter100us <= (others => '0');
                request_to_send_detected <= '1';
        end if;
        if(request_to_send_detected='1' and  ps2_clk_tb = 'Z' and  ps2_data_tb = 'Z' and data_clk_counter = 0)
        then
            request_to_send_detected <= '0';
        end if;
    end if;
    end process;
    --proces zliczający przesłane dane
    count_clocks: process(ps2_clk_tb)
    begin
        if falling_edge(ps2_clk_tb)
        then
            if(request_to_send_detected = '1')
            then
            data_clk_counter <= data_clk_counter+1;
            end if;
        end if;
        if rising_edge(ps2_clk_tb)
        then
            if(data_clk_counter = 11)
            then
            data_clk_counter <= natural(0);
            data_frame_complete <='1';
            end if;
        end if;
        if(ps2_clk_tb = 'Z' and ps2_data_tb = 'Z')
        then
            data_frame_complete <='0';
        end if;
    end process;
    --proces zbierające dane przychodzące z modułu ps2
    capture_data_from_host : process (ps2_clk_tb,ps2_data_tb)
    begin
        if (rising_edge(ps2_clk_tb) and data_clk_counter > 1 and data_clk_counter < 10 and data_frame_complete = '0' )
        then
            received_data(data_clk_counter-2) <= ps2_data_tb;
        end if;
        
    end process;
    
process is
begin
wait for 1ms;
reset_tb <= '1';

end process;

end Behavioral;
