----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 19.11.2024 14:23:10
-- Design Name: 
-- Module Name: PS2_PMOD - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.std_logic_unsigned.all;
use IEEE.NUMERIC_STD.ALL;
Library UNISIM;
use UNISIM.vcomponents.all;
-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;



entity PS2_PMOD is
port(
    ps2_clk  : inout std_logic;
    ps2_data : inout std_logic;
    
    reset : in std_logic;
    clock : in std_logic;--clock 50MHz
    
    y_axis_position : out std_logic_vector(9 downto 0);
    x_axis_position : out std_logic_vector(8 downto 0);
    left_button_state: out std_logic;
    middle_button_state: out std_logic;
    right_button_state: out std_logic;
    received : out std_logic_vector(7 downto 0)
);
end PS2_PMOD;

architecture Behavioral of PS2_PMOD is

constant reset_mouse: std_logic_vector(7 downto 0) := X"FF";
constant reset_mouse_parity: std_logic := '1';    
constant acknowledge : std_logic_vector (7 downto 0) := X"FA";
constant self_test_passed : std_logic_vector (7 downto 0) := X"AA";
constant self_test_passed_parity : std_logic := '0';
constant enable_data_reporting : std_logic_vector (7 downto 0) := X"F4";
constant enable_data_reporting_parity : std_logic:= '0';
constant device_id : std_logic_vector (7 downto 0) := X"00";



signal counter_100us: std_logic_vector(16 downto 0) := (others => '0');
signal data_frame_bit_counter: natural range 0 to 15 := 0;
signal data_frame: std_logic_vector (10 downto 0) :='1' & reset_mouse_parity & reset_mouse  &'0';

signal listen_to_reset_sequence_response: std_logic:='0';
signal received_data:std_logic_vector(7 downto 0) := (others => '0');

signal data_reporting_enabled: std_logic:= '0';
signal movement_byte_counter: natural range 0 to 2 := 0;
signal counter_2ms: std_logic_vector(24 downto 0) := (others => '0');

signal new_xy_dataset: std_logic:= '1';
signal  x_axis_movement : std_logic_vector(9 downto 0):= (others => '0');
signal y_axis_movement : std_logic_vector(8 downto 0):= (others => '0');
signal  x_sign_movement : std_logic:='0';
signal y_sign_movement : std_logic:='0';
signal x_axis_position_buffer : std_logic_vector(9 downto 0):= (others => '0');
signal y_axis_position_buffer : std_logic_vector(8 downto 0):= (others => '0');

signal alternative_data_buffer : std_logic_vector(7 downto 0):=(others => '0');
signal alternative_bit_counter : natural range 0 to 11:=0;
signal streaming_mode_entered_succesfully: std_logic:='0';
signal clk_last_value: std_logic:='0';
signal byte_counter : natural range 0 to 2:= 0;
type fsm_state is (
idle,first,second,second_bis,third,fourth,fifth,sixth,seventh,eighth,ninth,receive_data1,receive_data2
);
--iobuf signals
signal clk_o: std_logic;
signal clk_i: std_logic:='1';
signal clk_t: std_logic:='1';
signal data_o: std_logic;
signal data_i: std_logic:='1';
signal data_t: std_logic:='1';


signal state : fsm_state :=idle;

begin
IOBUF_inst_clk : IOBUF
generic map (
   DRIVE => 12,
   IOSTANDARD => "DEFAULT",
   SLEW => "SLOW")
port map (
   O => clk_o,     -- Buffer output
   IO => ps2_clk,   -- Buffer inout port (connect directly to top-level port)
   I => clk_i,     -- Buffer input
   T => clk_t      -- 3-state enable input, high=input, low=output
);

IOBUF_inst_data : IOBUF
generic map (
   DRIVE => 12,
   IOSTANDARD => "DEFAULT",
   SLEW => "SLOW")
port map (
   O => data_o,     -- Buffer output
   IO => ps2_data,   -- Buffer inout port (connect directly to top-level port)
   I => data_i,     -- Buffer input
   T => data_t      -- 3-state enable input, high=input, low=output
);
--procedure to start data transmition from controller to mouse
-- 1)   Bring the Clock line low for at least 100 microseconds.
-- 2)   Bring the Data line low.
-- 3)   Release the Clock line.
-- 4)   Wait for the device to bring the Clock line low.
-- 5)   Set/reset the Data line to send the first data bit
-- 6)   Wait for the device to bring Clock high.
-- 7)   Wait for the device to bring Clock low.
-- 8)   Repeat steps 5-7 for the other seven data bits and the parity bit
-- 9)   Release the Data line.
-- 10) Wait for the device to bring Data low.
-- 11) Wait for the device to bring Clock  low.
-- 12) Wait for the device to release Data and Clock
next_state_logic: process(clock)
begin
    if rising_edge(clock) then
            case state is
                when idle =>
                if(reset = '1' and listen_to_reset_sequence_response = '0') then
                    clk_t <='0';
                    state <= first;
                elsif(reset = '1' and listen_to_reset_sequence_response = '1') then
                    state <= receive_data1;--przełącz się w tryb odbioru danych
                 else
                    clk_t <='1';
                    data_t <= '1';
                 end if;
                when first =>--inicjalizacja nadawania danych do myszy, ściągamy zegar w dół
                    clk_i <= '0';
                    state <= second;
                when second =>
                    if(counter_100us < 5100)--czekamy ponad 100us
                    then
                        counter_100us<= counter_100us+1;
                    else
                        counter_100us <= (others => '0');
                        state <= second_bis;
                        data_t <= '0';--ściągamy linię danych w dół
                        data_i <= '0';
                    end if;
                when second_bis =>
                    clk_t <= '1';--odpuszczamy linię zegarową
                    state<=third;
                when third =>
                    
                    if(clk_o = '0') then
                        state <=fourth;--odpuszczamy linię danych
                        data_t <= '0';
                    end if;
                when fourth =>                
                    data_i <= data_frame(data_frame_bit_counter);--przesłanie bitu danych o numerze zależnym od indeksu
                    data_frame_bit_counter <= data_frame_bit_counter +1;

                    state <= fifth;
                when fifth =>
                    if(clk_o = '1') then
                        state <=sixth;--czekamy na narastające zbocze zegara
                    end if;
                when sixth =>
                if(clk_o = '0') then
                    if(data_frame_bit_counter < 10) then
                        state <=fourth;--wracamy do stanu 4 wysłać kolejny bit, chyba, że przesłano już wszystkie
                    else
                        data_frame_bit_counter <= natural(0);
                        data_t <= '1';
                        state <=seventh;
                        if(data_frame ='1'& enable_data_reporting_parity & enable_data_reporting &'0') 
                        then
                            data_reporting_enabled <= '1';--zapal flagę gdy skończono nadawać sygnał enable data reporting
                        end if;
                    end if;
                end if;
                when seventh=>
                    if(data_o = '0') then
                        state <=eighth;--poczekaj na ściągnięcie lini danych w dół
                    end if;
                when eighth =>
                    if(clk_o = '0') then
                        state <=ninth;--poczekaj na ściągnięcie lini zegarowej w dół
                    end if;
                when ninth=>
                    if(clk_o = '1' and data_o ='1')then
                        state <= idle;--wróć do stanu idle
                        listen_to_reset_sequence_response <='1';
                    end if;
                when receive_data1=>
                    if(clk_o = '0')
                    then--odbieraj dane  gdy zegar jest zerem, pomiń bit start, parity, stop
                        data_frame_bit_counter <= data_frame_bit_counter+1;
                        state <= receive_data2;
                        if(data_frame_bit_counter>0 and data_frame_bit_counter < 9)
                            then
                                received_data(natural(data_frame_bit_counter)-1) <= data_o;
                            end if;
                    end if;
                    
                when receive_data2=>
                    if(clk_o = '1')
                    then
                        state <= receive_data1;
                        if(data_frame_bit_counter>10 )then
                            data_frame_bit_counter <= natural(0);
                            --poniżej znajduje sięobsługa odbioru danych podczas inicjalizacji
                            if(received_data = self_test_passed and data_reporting_enabled = '0') then 
                                listen_to_reset_sequence_response <= '1';
                                state <= idle;
                            end if;
                            if(received_data = device_id and data_reporting_enabled = '0') then 
                                listen_to_reset_sequence_response <= '0';
                                data_frame<='1'& enable_data_reporting_parity & enable_data_reporting &'0';
                                state <= idle;
                            end if;

                        end if;
                    end if;
            end case;

    end if;
end process;

received<=alternative_data_buffer;-- wystawienie odebranych danych na wyjście dla prostszego debugowania

alternative_data_aquisition: process(clock,clk_o,alternative_bit_counter)
begin

    if rising_edge(clock)
    then
        clk_last_value<= clk_o;
        if(to_integer(unsigned(counter_2ms)) = 100000)
        then
            alternative_bit_counter <=natural(0);--wyzeruj licznik bitów jeśli nic nie przyszło przez 2ms(na wypadek błędu)
        end if;
    

        if (clk_o='0' and clk_last_value ='1')--zapisuj dane na opadającym zboczu
        then
            if(data_reporting_enabled = '1')
            then
                alternative_bit_counter<=alternative_bit_counter+1;

                if(alternative_bit_counter>0 and alternative_bit_counter < 9)
                then

                alternative_data_buffer(natural(alternative_bit_counter)-1)<= data_o;
                elsif(alternative_bit_counter = 10)
                then
                    alternative_bit_counter <=natural(0);
                    --byte_counter<= natural(0);
                end if;

            end if;
        end if;
        if (clk_o='1' and clk_last_value ='0')
        then
            if(alternative_bit_counter = 9)then
                if(streaming_mode_entered_succesfully='0')
                then
                    if(alternative_data_buffer = acknowledge)
                    then
                        streaming_mode_entered_succesfully<= '1';
                    end if;
                else
                --rozdzielenie odebranych danych na odpowiednie pola
                    case byte_counter is
                                    when 0  => 
                                        new_xy_dataset<='1';
                                        left_button_state <= alternative_data_buffer(0);
                                        right_button_state <= alternative_data_buffer(1);
                                        middle_button_state <= alternative_data_buffer(2);
                                        x_sign_movement <= alternative_data_buffer(4);
                                        y_sign_movement <= alternative_data_buffer(5);
                                        byte_counter <= byte_counter + 1;
                                    when  1 => 
                                        if(x_sign_movement = '0')
                                        then
                                            x_axis_movement <= alternative_data_buffer & "00";
                                        else
                                            x_axis_movement <= std_logic_vector(unsigned(2**10-alternative_data_buffer) & "00");
                                        end if;
                                        byte_counter <= byte_counter + 1;
                                    when others => 
                                        if(y_sign_movement = '0')
                                        then
                                            y_axis_movement <= alternative_data_buffer & "0";
                                        else
                                            y_axis_movement <= std_logic_vector(unsigned(2**9-alternative_data_buffer) & "0");
                                        end if;
                                        new_xy_dataset <= '0';
                                        byte_counter <= 0;
                                    end case;
                end if;

            end if;
        end if;
end if;
end process;


count_time_from_last_received_dataset: process(clock)
begin

   if rising_edge(clock)
   then
       if(clk_o = '1')
       then
           if(to_integer(unsigned(counter_2ms)) < 100000)
           then
               counter_2ms<=counter_2ms+1;

           end if;
       else            
           counter_2ms<= (others => '0');
       end if;
   end if;

end process;

assign_xy_output: process(clock)
begin
    if rising_edge(clock)
    then
        y_axis_position <= x_axis_position_buffer;
        x_axis_position <= y_axis_position_buffer;
    end if;
end process;

send_xy_data: process(new_xy_dataset,reset)
begin
if(reset = '0')
then 
    x_axis_position_buffer <= (others => '0');
    y_axis_position_buffer <= (others => '0');
else
    if falling_edge(new_xy_dataset)
    then
        if(x_sign_movement ='1')
        then
            if(x_axis_position_buffer < 511)
            then
                if(x_axis_position_buffer < 256 and x_axis_position_buffer > 0)
                then
                    x_axis_position_buffer<= std_logic_vector(unsigned(x_axis_position_buffer) + to_unsigned(4, x_axis_position_buffer'length));
                else
                    x_axis_position_buffer<= std_logic_vector(unsigned(x_axis_position_buffer) + to_unsigned(8, x_axis_position_buffer'length));
                end if;
            end if;
        else



            if(x_axis_position_buffer > 8)
            then
                if(x_axis_movement < 256 and x_axis_position_buffer > 0)
                then
                    x_axis_position_buffer<= std_logic_vector(signed(x_axis_position_buffer) - to_signed(4, x_axis_position_buffer'length));
                else
                    x_axis_position_buffer<= std_logic_vector(signed(x_axis_position_buffer) - to_signed(8, x_axis_position_buffer'length));
                end if;
            end if;
        end if;

        if(y_sign_movement ='1')
        then


            if(y_axis_position_buffer < 1015)
            then
                if(y_axis_movement < 511 and y_axis_movement > 0)
                then
                    y_axis_position_buffer<= std_logic_vector(unsigned(y_axis_position_buffer) + to_unsigned(2, y_axis_position_buffer'length));
                else
                    y_axis_position_buffer<= std_logic_vector(unsigned(y_axis_position_buffer) + to_unsigned(4, y_axis_position_buffer'length));
                end if;
            end if;
        else
        
            if(y_axis_position_buffer > 8)
            then
                if(y_axis_movement < 511 and y_axis_movement > 0)
                then
                     y_axis_position_buffer<= std_logic_vector(unsigned(y_axis_position_buffer) - to_unsigned(2, y_axis_position_buffer'length));
                else
                    y_axis_position_buffer<= std_logic_vector(unsigned(y_axis_position_buffer) - to_unsigned(4, y_axis_position_buffer'length));
                end if;
            end if;
        end if;
    end if;
end if;
end process;

end Behavioral;
