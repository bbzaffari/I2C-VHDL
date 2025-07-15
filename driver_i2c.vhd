--------------------------------------------------------------------------------------------    
--  Nome: Bruno Bavaresco Zaffari
--  Projetos de sistemas integrados 2
--  Mouse i2c_driver 
--------------------------------------------------------------------------------------------
library ieee;

use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity driver_i2c is 
	generic(
		CLOCK_DIVISOR : integer := 500,
		CONTROL_CODE : std_logic_vector(3 downto 0) := "1010",
		CHIP_SLCT : std_logic_vector(2 downto 0) := "000"
	);
	port (
		clock: in std_logic;
		reset: in std_logic;
		
		wr_data: in std_logic_vector(7 downto 0);
		wr_addr: in std_logic_vector(7 downto 0);
		wr_enable: in std_logic;
		
		rd_data: out std_logic_vector(7 downto 0);
		rd_addr: in std_logic_vector(7 downto 0);
		rd_enable: in std_logic;
		
		done: out std_logic;
		scl: out std_logic;
		sda: inout std_logic
	);
end driver_i2c;

architecture rtc of driver_i2c is
	-----------------------------------------------------------------------------------------------
    type TX_STATES is (TX_START, TX_CONTROL_BYTE, TX_ADDR, TX_DATA, TX_NACK, TX_STOP, TX_NULL);
	type RX_STATES is (RECEIVE_ACK, RECEIVE_DATA, RX_NULL);
	type MODE is (TX, RX, IDLE, DELAY, ERROR);
	--==============================================
    signal TX_STATE, TX_SAVE : TX_STATES;
	signal RX_STATE, RX_SAVE : RX_STATES;
	signal which,   SAVE_WITCH	: MODE := IDLE;
	--==============================================
	constant W  : integer := 2;
	constant R  : integer := 1;
    signal   WR : integer in range 0 to 2; 
	--==============================================
	constant START_BIT  : std_logic := '0';
	constant STOP_BIT   : std_logic := '1';
	--==============================================
	signal sda_out : std_logic := '1';
	signal sda_oe  : std_logic := '1';
	--==============================================
	-----------------------------------------------------------------------------------------------
    signal scl_i2c : std_logic    := '0';
    signal clk_counter : integer  := 0;
	
	signal dataTOwrite: std_Logic_vector(7 downto 0) := (others => '0');
	signal read_buffer: std_Logic_vector(7 downto 0) := (others => '0');
    signal control_byte : std_logic_vector(7 downto 0);
	signal addr : std_Logic_vector(7 downto 0);
	
    signal ACK :std_logic := '0';
	
	signal FLAG_TO_START :integer in range 0 to 3 := 0;
	signal FLAG_OK :std_logic := '0';
    signal counter : integer := 0;
	
	signal DELAY_COUNT_DOWN :integer in range 0 to 30;
	
	-- =================================DEBUG===============================================
	constant CR : string := character'val(13) & character'val(10); -- Carriage Return + Line Feed
	-- Para std_logic
	function to_str(bit : std_logic) return string is
	begin
		return std_ulogic'image(bit);
	end function;

	-- Para std_logic_vector
	function to_str(vec: std_logic_vector) return string is 
		variable s : string(1 to vec'length);
	begin
		for i in vec'range loop
			s(i - vec'low + 1) := std_ulogic'image(vec(i))(2);  -- extrai o caractere '0' ou '1'
		end loop;
		return s;
	end function;
	-- =================================DEBUG===============================================
	
begin
	----------------------------------------------------------------------------------
	dataTOwrite <= wr_data when wr_enable = '1' and rd_enable = '0' else 
			       dataTOwrite;
			
	addr <= wr_addr when wr_enable = '1' and rd_enable = '0' else 
			rd_addr when wr_enable = '0' and rd_enable = '1' else
			addr;
			
	sda <= sda_out when sda_oe = '1' else 'Z'; -- tri-state
			
	----------------------------------------------------------------------------------
	-- CLOCK DIVISOR
    clk_divisor: process(clock, reset)
	begin
		if reset = '1' then
			clk_counter <= 0;
			scl_i2c     <= '0';
			
		elsif rising_edge(clock) then					
			if clk_counter >= (CLOCK_DIVISOR/2 -1) then
				clk_counter <= 0;
				scl_i2c     <= not scl_i2c;
			else
				clk_counter <= clk_counter + 1;
			end if;
		end if;
	end process clk_divisor;
	
	scl <= '1' when which = IDLE or TX_STATE = TX_START or TX_STATE = TX_STOP 
			else scl_i2c;
			
	--========================================================================
	ignição: process(wr_enable, rd_enable, FLAG_OK) -- Indentifica se recebeu requisicao
	begin
		if FLAG_OK = '1' then
			FLAG_TO_START <= 0;  -- IDLE
			control_byte <= (others => '0');
		elsif wr_enable = '1' and rd_enable = '1' then
			FLAG_TO_START <= 1;  -- ERRO
			control_byte <= (others => '0');
		elsif wr_enable = '1' then
			WR <= W;		     -- ATIVADO EM W
			FLAG_TO_START <= 2; 
			control_byte <= CONTROL_CODE & CHIP_SLCT & '0';
		elsif rd_enable = '1' then
			WR <= R;			 -- ATIVADO EM R
			FLAG_TO_START <= 2;  
			control_byte <= CONTROL_CODE & CHIP_SLCT & '1';
		else
			WR <= 0;
			FLAG_TO_START <= 3;  -- NÃO INICIALIZADO
		end if;
		report "[IGN] WR_EN=" & to_str(wr_enable) & 
				CR & "    RD_EN=" & to_str(rd_enable) & 
				CR & "    CB=" & to_str(control_byte) & 
				CR & "    FTS=" & integer'image(FLAG_TO_START) & 
				CR & "    WR=" & integer'image(WR);

	end process ignição;
	----------------------------------------------------------------------------------
	
	-------------------------------------------------------------------------------------------------------------------
	----------------------------------------<   <  < < F  S  M > >  >   >----------------------------------------------
	-------------------------------------------------------------------------------------------------------------------
	
	FSM: process(scl_i2c, reset) is 
		variable ack_temp : std_logic;
	begin
		-- Reset assíncrono: retorna todos os sinais à condição inicial
		if reset = '1' then
			read_buffer<=(others=> '0');
			TX_STATE <= TX_NULL;
			RX_STATE <= RX_NULL;
			which    <= IDLE;
			sda_oe   <= '1'; -- habilita escrita
			sda_out  <= '1';
			ACK      <= '1'; -- valor padrão do barramento I2C (pull-up)
			FLAG_OK  <= '1';
			done     <= '0'; -- Limpa sinal de conclusão
			counter  <= 8;
			
		elsif rising_edge(scl_i2c) then
			done <= '0'; -- padrão
			case which is
			-- IDLE ---------------------------------------------------------------------------------------
				when IDLE => 
					-- INIT
					read_buffer<=(others=> '0');
					TX_STATE <= TX_NULL;
					RX_STATE <= RX_NULL;
					which    <= IDLE;
					sda_oe   <= '1'; -- habilita escrita
					sda_out  <= '1';
					ACK      <= '1'; -- valor padrão do barramento I2C (pull-up)
					FLAG_OK  <= '1';
					counter  <= 7;
					------------------------------------------------------------
					if (FLAG_TO_START = 2) then
						which <= TX;
						TX_STATE <= TX_START; 
						sda_oe <= '1'; -- habilita escrita
					elsif (FLAG_TO_START = 1) then  -- ERROR
						--+++++++++++++++++++++++++++++++
						which <= ERROR;
						DELAY_COUNT_DOWN <= 27; -- ou era menos? 
						report "FSM Entered ERROR state. Countdown: " & integer'image(DELAY_COUNT_DOWN) severity warning;
						-------------------------
						SAVE_WITCH <= IDLE;
						TX_SAVE <= TX_NULL; 
						RX_SAVE <= RX_NULL;
						--+++++++++++++++++++++++++++++++
					end if
			-- DELAY ---------------------------------------------------------------------------------------
				when DELAY => 
					if (DELAY_COUNT_DOWN = 0) then
						which <= SAVE_WITCH;
						TX_STATE <= TX_SAVE; 
						RX_STATE <= RX_SAVE;
					else 
						DELAY_COUNT_DOWN <= DELAY_COUNT_DOWN - 1;
					end if	
					
			-- ERROR ---------------------------------------------------------------------------------------
				when ERROR => 
					if (DELAY_COUNT_DOWN = 0) then
						which <= SAVE_WITCH;
						TX_STATE <= TX_SAVE; 
						RX_STATE <= RX_SAVE;
					else 
						DELAY_COUNT_DOWN <= DELAY_COUNT_DOWN - 1;
					end if
			--================================================================================================
				when TX =>
					----------------------------------------------------------------------------------------------
					-------------------------------- <<<<<TRANSCEIVER>>>>> ---------------------------------------
					
					-- =================================DEBUG===============================================
					report "TX_STATE: " & 
					(case TX_STATE is
						when TX_START         => "TX_START"
						when TX_CONTROL_BYTE  => "TX_CONTROL_BYTE"
						when TX_ADDR          => "TX_ADDR"
						when TX_DATA          => "TX_DATA"
						when TX_NACK          => "TX_NACK"
						when TX_STOP          => "TX_STOP"
						when others           => "TX_NULL"
					end case) & 
					" | SDA_OUT: " & to_str(sda_out) & " | COUNTER: " & integer'image(counter);
					-- =================================DEBUG===============================================
					
					-- Ação em borda de subida do SCL: envio de bits
					case TX_STATE is
						------------------------------------------------------------------------ TX_START
						when TX_START => -- Envio do start bit (SDA = 0 com SCL alto)
							sda_out <= START_BIT;
							TX_STATE <= TX_CONTROL_BYTE;
							FLAG_OK <= '1';
							counter <= 7; 
							
						------------------------------------------------------------------------ TX_CONTROL_BYTE
						when TX_CONTROL_BYTE => -- Envio do byte de controle (7 bits + R/W)
							if (counter >= 1) and (counter <= 8) then -- 8 ate 1
								report "[TX] control_byte(" & integer'image(counter-1) & ")"  & control_byte(addr(counter -1));-- DEBUG
								sda_out <= control_byte(counter-1);
								
								if counter = 0 then
									sda_oe <= '0'; -- tri-state/libera barramento para ACK, solta SDA
									------------------------------------------------------
									which <= RX;
									RX_STATE <= RECEIVE_ACK; 
									counter <= 7; 
									ACK <= '1';
									-----------------------------------------------------
								else 
									counter <= counter - 1;
								end if;		
							end if;
						------------------------------------------------------------------------ TX_ADDR
						when TX_ADDR => -- Envio do endereço (8 bits)
							if (counter >= 0) and (counter <= 7) then -- 7 ate 0
								report "[TX] addr(" & integer'image(counter) & ")"  & to_str(addr(counter -1));-- DEBUG
								sda_out <= addr(counter); -- 7 ate 0
								
								if counter = 0 then
									sda_oe <= '0'; -- tri-state/libera barramento para ACK, solta SDA
									------------------------------------------------------
									which <= RX;
									RX_STATE <= RECEIVE_ACK; 
									counter <= 7; 
									ACK <= '1';
									-----------------------------------------------------
								else 
									counter <= counter - 1;
								end if;							
							end if;
						------------------------------------------------------------------------ TX_DATA
						when TX_DATA => -- Envio do dado (8 bits)
							if counter >= 0 and counter <= 7 then -- 8 ate 1
								report "[TX] dataTOwrite(" & integer'image(counter) & ")"  & to_str(dataTOwrite(counter -1));-- DEBUG
								sda_out <= dataTOwrite(counter);
								
								if counter = 0 then
									sda_oe <= '0'; -- tri-state/libera barramento para ACK, solta SDA
									------------------------------------------------------
									which <= RX;
									RX_STATE <= RECEIVE_ACK; 
									counter <= 7; 
									ACK <= '1';
									-----------------------------------------------------
								else 
									counter <= counter - 1;
								end if;	
							end if;
						------------------------------------------------------------------------ TX_NACK
						when TX_NACK => -- Envia NACK para indicar fim da leitura
							sda_out <= '1';
							TX_STATE <= TX_STOP;      -- Finaliza comunicação
						------------------------------------------------------------------------ TX_STOP 
						when TX_STOP => -- Envio do stop bit (SDA sobe com SCL alto)
							sda_out <= STOP_BIT;
							done <= '1';-- Indica fim da transação
							report "[TX] Transaction Completed. Returning to IDLE. Done asserted.";
							which <= IDLE;
						------------------------------------------------------------------------ OTHERS	
						when others =>
							which <= IDLE;
						end case;-- TX
					
				--================================================================================================
				when RX =>
					----------------------------------------------------------------------------------------------
					---------------------------------- <<<<<RECEIVER>>>>> ----------------------------------------
					
					-- =================================DEBUG===============================================
					report "RX_STATE: " & 
					(case RX_STATE is
						when RECEIVE_ACK  => "RECEIVE_ACK"
						when RECEIVE_DATA => "RECEIVE_DATA"
						when others       => "RX_NULL"
					end case) & 
					" | SDA: " & to_str(sda) & " | COUNTER: " & integer'image(counter);
					-- =================================DEBUG===============================================
					
					case RX_STATE is
						------------------------------------------------------------------------  RX_ACK
						when RECEIVE_ACK => -- captura o bit de ACK (esperado '0')						
							if sda /= '0' then 
								which <= IDLE;
							else
								ACK<=sda;
								report "[RX] ACK <=" & to_str(read_buffer(sda));-- DEBUG
								
								case TX_STATE is
									when TX_CONTROL_BYTE => 
										sda_oe <= '1'; -- habilita escrita
										which <= TX;
										TX_STATE <= TX_ADDR;
										
									when TX_ADDR =>
									--==============================
										if WR = W then
											sda_oe <= '1'; -- habilita escrita
											which <= TX;
											TX_STATE <= TX_DATA;
											
										elsif WR = R then
											counter <= 7;  
											RX_STATE <= RX_DATA;
											read_buffer<=(others=> '0');
										end if;
									--==============================
									when TX_DATA =>
										sda_oe <= '1'; -- habilita escrita
										which <= TX;
										TX_STATE <= TX_NACK;
										
									when others =>
										which <= IDLE;
							end if;
						------------------------------------------------------------------------  RX_DATA
						when RECEIVE_DATA =>
							if (counter >= 0) and (counter <= 7) then -- 7 ate 0
								read_buffer(counter) <= sda; -- bits 7 até 0
								report "[RX] read_buffer(" & integer'image(counter) & ")"  & to_str(read_buffer(counter -1));-- DEBUG
								
								if counter = 0 then    	
									report "Read completed: Data = " & to_str(read_buffer);
									-----------------------------------------------
									rd_data<= read_buffer;
									sda_oe <= '1'; -- habilita escrita
									TX_STATE <= TX_NACK;			
									which  <= TX;
									counter <= 7;  
									-----------------------------------------------
								else
									counter <= counter - 1;
								end if;
								
							end if;
						when others =>
							which <= IDLE;
						end case; -- RX	
				--+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
				when others =>
					which <= IDLE;
			end case;
			end if;
		end if;
	end process FSM;

-----------------------------------------------------------------------------------------------------------------------


end rtc;