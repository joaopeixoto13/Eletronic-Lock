#include <REG51F380.H>

CSEG AT 0H
	LJMP MAIN
	
CSEG AT 002BH																		//Vetor de código associado à Interrupt do Timer 2 -> Interrupção Vetorizada
	LJMP ISR_TIMER2

	
CSEG AT 1000H
			       //  0    1    2    3    4    5    6    7    8    9    		
	ARRAY_DIGITS: DB 0xC0,0xF9,0xA4,0xB0,0x99,0x92,0x82,0xF8,0x80,0x90				//Declaração dos termos do ARRAY_DIGITS
		
CSEG AT 1050H
			  //  1     2     3     4
	SEC_KEY: DB 0x01, 0x02, 0x03, 0x04												//Chave de Segurança -> '123'
	

CSEG AT 200H
	
STATE   	DATA 30H
N_STATE 	DATA 31H																
INDEX   	DATA 32H 																//Variável auxiliar
TAM_KEY 	DATA 33H																//Tamanho da chave 
MAX_30  	DATA 34H																//Multiplicador para gerar 30s
MAX_025 	DATA 35H																//Multiplicador para gerar 0,25s
ATTEMPS 	DATA 36H															 	//Total de tentaivas para desbloquear a fechadura
TAM_REC_KEY DATA 37H																//Tamanho da chave de RECOVERY_CONDITION
VAR 		DATA 38H	
	
STORAGE_NUMBERS 		  IDATA 80H													//Guarda os numeros da chave em IDATA

STORAGE_USER_KEY 		  IDATA 0A3H												//Guarda o código da fechadura
	
STORAGE_NUMBERS_RECOVER   IDATA 0C6H												//Guarda o código de Recover_Condition que o utilizador coloca 		

STORAGE_RECOVER_KEY 	  IDATA 0E9H												//Guarda o código da Recover_Condition


K_SET   EQU P0.6																	//Define o nome da porta P0.6 como K_SET
K_LOAD  EQU P0.7																	//Define o nome da porta P0.7 como K_LOAD
DISPLAY EQU P2																		//Define o nome da porta P2 como DISPLAY
BIN     EQU P1																		//Define o nome da porta P1 como BIN
																	
	
	
S_LOCKED  EQU 0
S_DECRYPT EQU 1
S_OPEN    EQU 2
S_FAIL	  EQU 3
S_BLOCKED EQU 4
S_ENCRYPT EQU 5
S_RECOVER EQU 6


//BITS
SET_PREMIDO  EQU 20H.0																//BIT responsável para saber se K_SET foi premido
LOAD_PREMIDO EQU 20H.1																//BIT responsável para saber se K_LOAD foi premido
EXAUSTED     EQU 20H.2																//BIT responsável por saber se o utilizador esgotou as 3 tentaivas para entrar
VALID        EQU 20H.3																//BIT responsável por saber se a chave que o utilizador inseriu é válida 
TIMEOUT      EQU 20H.4																//BIT responsável por saber se houve timeout, se passaram os 30s 
SAFE         EQU 20H.5																//BIT responsável por saber se utilizador mudou a chave
TIM_OPEN     EQU 20H.6																//BIT responsável para o Timer do estado STATE_OPEN
TIM_FAIL     EQU 20H.7																//BIT responsável para o Timer do estado STATE_FAIL
TIM_BLOCKED  EQU 21H.0																//BIT responsável para o Timer do estado STATE_BLOCKED
FLAG_RECOVER EQU 21H.1																//BIT responsável pela RECOVERY_CONDITION
SAFE_RECOVER EQU 21H.2																//BIT responsável pela por repor SEC_KEY depois de código válido na RECOVER_CONDITION
//


//---------------------------------------------Configuração para as interrupções dos Estados---------------------------------------------------------------------------	

ISR_TIMER2:
	PUSH ACC
	PUSH PSW
	
	JB TIM_OPEN, ISR_TIMER2_OPEN					//Se TIM_OPEN = 1 -> STATE OPEN
	JB TIM_FAIL, ISR_TIMER2_FAIL					//Se TIM_FAIL = 1 -> STATE FAIL
	JB TIM_BLOCKED, ISR_TIMER2_BLOCKED				//Se TIM_BLOCKED = 1 -> STATE BLOCKED
	
	
		ISR_TIMER2_OPEN:							//Configuração para STATE OPEN -> durante 30s ponto decimal a piscar num ritmo de 500ms
			CLR  TF2H
			DJNZ MAX_025, FIM_ISR_TIMER2_OPEN
			CPL P2.7
			MOV MAX_025, #25
			DJNZ MAX_30, FIM_ISR_TIMER2_OPEN
			SETB TIMEOUT
			
			FIM_ISR_TIMER2_OPEN:
				POP PSW
				POP ACC
				RETI
				
		ISR_TIMER2_FAIL:							//Configuração para STATE FAIL -> espera de 30s
			CLR  TF2H
			DJNZ MAX_025, FIM_ISR_TIMER2_FAIL
			MOV MAX_025, #25
			DJNZ MAX_30, FIM_ISR_TIMER2_FAIL
			SETB TIMEOUT
			
			FIM_ISR_TIMER2_FAIL:
				POP PSW
				POP ACC
				RETI
				
				
		ISR_TIMER2_BLOCKED:							//Configuração para STATE BLOCKED -> espera indeterminada -> até RESET que ativa RECOVERY_CONDITION <- e colocar ponto decimal a piscar num ritmo de 500ms
			CLR  TF2H
			DJNZ MAX_025, FIM_ISR_TIMER2_BLOCKED
			CPL P2.7
			CPL P1.0
			MOV MAX_025, #25
			
			FIM_ISR_TIMER2_BLOCKED:
				POP PSW
				POP ACC
				RETI
			
//---------------------------------------------Configuração para as interrupções dos Estados---------------------------------------------------------------------------	
			
	

MAIN:
	ACALL CONFIGS																						//Invoca a label 'CONFIGS'
	ACALL OSCILATOR_INIT
	ACALL TIMER2_INIT
	CLR C																								//CLR C
	SETB K_SET																							//Coloca a porta P0.6 com o valor lógico '1' -> Desligada - Consultar Datasheet
	SETB K_LOAD																							//Coloca a porta P0.7 com o valor lógico '1' -> Desligada - Consultar Datasheet
	CLR EXAUSTED
	CLR VALID
	CLR TIMEOUT
	CLR SAFE
	CLR TIM_OPEN
	CLR TIM_FAIL
	CLR TIM_BLOCKED
	CLR SAFE_RECOVER
	MOV STATE, #S_LOCKED																				//Colocar estado atual no estado S_LOCKED
	MOV N_STATE, #S_LOCKED																				//Colocar próximo estado no estado S_LOCKED
	MOV INDEX, #0																						//Colocar variavél 'INDEX' a 0
	MOV BIN, #0																							//Colocar na porta P1 -> BIN -> tudo a zero -> desligar todos os bits
	MOV TAM_KEY, #5
	MOV VAR, #0
	MOV MAX_30, #120
	MOV MAX_025, #25
	MOV ATTEMPS, #3
	MOV TAM_REC_KEY, #9
	ACALL PUT_RECOVER_KEY																				//Chamada da subrotina responsável por colocar a Recover_Key 
	JB FLAG_RECOVER, ST_RECOVER																			//Se FLAG_RECOVER = 1 -> ST_RECOVER
	JMP ENCODE_FSM
	

//---------------------------------------------'SWITCH CASE' para os Estados---------------------------------------------------------------------------	
ENCODE_FSM:
	MOV DPTR, #SWITCH_STATE																				//Colocar em DPTR endereço da primeiria instrução da lebel SWITCH_STATE
	MOV STATE, N_STATE																					//Colocar N_STATE em STATE
	MOV A, STATE																						//Colocar STATE no acumulador
	RL A																								//RL porque cada AJMP ocupa 2 Bytes, daí RL para multiplicar por 2
	JMP @A+DPTR

SWITCH_STATE:
	AJMP STATE_LOCKED
	AJMP STATE_DECRYPT
	AJMP STATE_OPEN
	AJMP STATE_FAIL
	AJMP STATE_BLOCKED
	AJMP STATE_ENCRYPT
	AJMP STATE_RECOVER
	
//---------------------------------------------'SWITCH CASE' para os Estados---------------------------------------------------------------------------	



//---------------------------------------------Preparação para o 'STATE_RECOVER'---------------------------------------------------------------------------	
ST_RECOVER:
	CLR EA
	CLR ET2
	CLR TIM_BLOCKED
	MOV DISPLAY, #0FFH
	MOV DPTR, #ARRAY_DIGITS
	MOV N_STATE, #S_RECOVER
	JMP ENCODE_FSM
//---------------------------------------------Preparação para o 'STATE_RECOVER'---------------------------------------------------------------------------	
	


//---------------------------------------------Inicio Estado STATE_LOCKED------------------------------------------------------------------------------	
STATE_LOCKED:
	MOV DISPLAY, #0xC7		//Coloca 'L' no ecrã
	JBC SAFE_RECOVER, PUT_SEC_KEY_ON_USER_KEY
	ACALL VALIDA_CODIGO
	JNB SAFE, PUT_SEC_KEY_ON_USER_KEY
	JMP LOOP_STATE_LOCKED
	
	VALIDA_CODIGO:
		ACALL READ_FLASH_FLAG
		CJNE A, #13, CODIGO_INVALIDO
		SETB SAFE
		RET
		
		CODIGO_INVALIDO:
			CLR SAFE
			RET
		
	LOOP_STATE_LOCKED:
		LCALL LOOP
		JBC LOAD_PREMIDO, STATE_LOCKED_LOAD
		JMP LOOP_STATE_LOCKED
		
		STATE_LOCKED_LOAD:
			MOV N_STATE, #S_DECRYPT
			JMP ENCODE_FSM
		
		
		
		PUT_SEC_KEY_ON_USER_KEY:
			MOV DPTR, #SEC_KEY
			MOV R1, #STORAGE_USER_KEY
			MOV A, #0
			MOVC A, @A + DPTR
			ACALL ENCRYPT_NUMBERS
			MOV @R1, A
			MOV A, #1
			INC R1
			MOVC A, @A + DPTR
			ACALL ENCRYPT_NUMBERS
			MOV @R1, A
			MOV A, #2
			INC R1
			MOVC A, @A + DPTR
			ACALL ENCRYPT_NUMBERS
			MOV @R1, A
			MOV A, #3
			INC R1
			MOVC A, @A + DPTR
			ACALL ENCRYPT_NUMBERS
			MOV @R1, A		
			ACALL ERASE_FLASH				//limpar a página da FLASH
			ACALL WRITE_FLASH				//Escrever o código - Encriptado - na FLASH
			ACALL WRITE_FLASH_FLAG
			JMP LOOP_STATE_LOCKED
		
	
//---------------------------------------------Fim Estado STATE_LOCKED------------------------------------------------------------------------------	




//---------------------------------------------Inicio Estado STATE_DECRYPT------------------------------------------------------------------------------	

STATE_DECRYPT:
	MOV DPTR, #ARRAY_DIGITS
	MOV R0, #STORAGE_NUMBERS
	MOV R1, #STORAGE_USER_KEY
	MOV INDEX, #0
	MOV R5, #0
	LCALL SHOW_DIGITS
	JMP LOOP_STATE_DECRYPT
	
	LOOP_STATE_DECRYPT:
		CJNE R5, #4, LOOP_STATE_DECRYPT_CONTINUE
		MOV TAM_KEY, #1
		JMP STATE_DECRYPT_LOAD
		
		LOOP_STATE_DECRYPT_CONTINUE:
		LCALL LOOP
		JBC SET_PREMIDO, STATE_DECRYPT_SET
		JBC LOAD_PREMIDO, STATE_DECRYPT_LOAD
		JMP LOOP_STATE_DECRYPT

		STATE_DECRYPT_SET:
			LCALL SHOW_DIGITS
			JMP LOOP_STATE_DECRYPT

		STATE_DECRYPT_LOAD:
			INC R5
			DJNZ TAM_KEY, PUT_NUMBERS
			MOV R5, #0
			MOV DPTR, #0x7A18
			MOV R0, #STORAGE_NUMBERS
			MOV INDEX, #0
			ACALL READ_FLASH
			ACALL DECRYPT_NUMBERS
			CLR C
			SUBB A, @R0
			JNZ FALHA 		//Se 1ºdigito inserido na fechadura != 1ºdigito do código da chave -> FALHA
			INC R0
			MOV INDEX, #1
			ACALL READ_FLASH
			ACALL DECRYPT_NUMBERS
			CLR C
			SUBB A, @R0
			JNZ FALHA 		//Se 2ºdigito inserido na fechadura != 2ºdigito do código da chave -> FALHA
			INC R0
			MOV INDEX, #2
			ACALL READ_FLASH
			ACALL DECRYPT_NUMBERS
			CLR C
			SUBB A, @R0
			JNZ FALHA 		//Se 3ºdigito inserido na fechadura != 3ºdigito do código da chave -> FALHA
			INC R0
			MOV INDEX, #3
			ACALL READ_FLASH
			ACALL DECRYPT_NUMBERS
			CLR C
			SUBB A, @R0
			JNZ FALHA 		//Se 4ºdigito inserido na fechadura != 4ºdigito do código da chave -> FALHA
			SETB VALID
			MOV N_STATE, #S_OPEN
			MOV ATTEMPS, #3
			MOV INDEX, #0
			MOV TAM_KEY, #5
			JMP ENCODE_FSM
			
			FALHA:
				MOV N_STATE, #S_FAIL
				CLR VALID
				MOV A, ATTEMPS
				DEC A
				MOV ATTEMPS, A
				MOV INDEX, #0
				MOV TAM_KEY, #5
				JMP ENCODE_FSM
			


			PUT_NUMBERS:
				MOV A, INDEX
				DEC A				//visto que depois de fazer, por exemplo, INDEX=0, INC INDEX para futura iteração
				MOV @R0, A
				INC R0
				JMP LOOP_STATE_DECRYPT
				
//---------------------------------------------Fim Estado STATE_DECRYPT------------------------------------------------------------------------------	





//---------------------------------------------Inicio Estado STATE_OPEN------------------------------------------------------------------------------	

STATE_OPEN:
	MOV DISPLAY, #0xA3		//Coloca 'o' no DISPLAY
	MOV MAX_30, #120
	SETB TIM_OPEN 			//Colocar Timer 2 para STATE OPEN
	SETB ET2 				//Ligar Interrupt para o Timer 2
	SETB EA					//Enable Global Interrupt
	JMP LOOP_STATE_OPEN
	
	LOOP_STATE_OPEN:
		JNB K_LOAD, K_LOAD_PRESSED
		JNB K_SET, K_SET_PRESSED
		JBC TIMEOUT, LABEL_TIMEOUT
		JMP LOOP_STATE_OPEN 
		
		LABEL_TIMEOUT:
			CLR ET2 		//Desligar Interrupt para o Timer 2
			CLR EA			//Disable Global Interrupt
			CLR TIM_OPEN	
			JMP SWAP_KEY
		
			SWAP_KEY:
				MOV N_STATE, #S_ENCRYPT
				MOV INDEX, #0
				JMP ENCODE_FSM
				
		K_SET_PRESSED:
			JNB K_SET, $
			CLR ET2 		//Desligar Interrupt para o Timer 2
			CLR EA			//Disable Global Interrupt
			CLR TIM_OPEN	
			JMP SWAP_KEY

		K_LOAD_PRESSED:
			JNB K_LOAD, $
			CLR ET2 		//Desligar Interrupt para o Timer 2
			CLR EA			//Disable Global Interrupt
			CLR TIM_OPEN
			MOV N_STATE, #S_LOCKED
			SETB SAFE
			JMP ENCODE_FSM


//---------------------------------------------Fim Estado STATE_OPEN------------------------------------------------------------------------------	





//---------------------------------------------Inicio Estado STATE_ENCRYPT------------------------------------------------------------------------------	

STATE_ENCRYPT:
	MOV DPTR, #ARRAY_DIGITS
	MOV R0, #STORAGE_NUMBERS
	MOV R1, #STORAGE_USER_KEY
	MOV R5, #0
	LCALL SHOW_DIGITS
	JMP LOOP_STATE_ENCRYPT
	
	LOOP_STATE_ENCRYPT:
		CJNE R5, #4, LOOP_STATE_ENCRYPT_CONTINUE
		MOV TAM_KEY, #1
		JMP STATE_ENCRYPT_LOAD
		
		LOOP_STATE_ENCRYPT_CONTINUE:
		LCALL LOOP
		JBC SET_PREMIDO, STATE_ENCRYPT_SET
		JBC LOAD_PREMIDO, STATE_ENCRYPT_LOAD
		JMP LOOP_STATE_ENCRYPT
	
		STATE_ENCRYPT_SET:
			LCALL SHOW_DIGITS
			JMP LOOP_STATE_ENCRYPT
			
		STATE_ENCRYPT_LOAD:
			INC R5
			DJNZ TAM_KEY, PUT_NUMBERS_ENCRYPT
			MOV R5, #0
			MOV R0, #STORAGE_NUMBERS
			MOV A, @R0
			MOV @R1, A
			INC R0
			INC R1
			MOV A, @R0
			MOV @R1, A
			INC R0
			INC R1
			MOV A, @R0
			MOV @R1, A
			INC R0
			INC R1
			MOV A, @R0
			MOV @R1, A
			ACALL ERASE_FLASH				//limpar a página da FLASH
			ACALL WRITE_FLASH				//Escrever o código - Encriptado - na FLASH
			ACALL WRITE_FLASH_FLAG
			MOV INDEX, #0
			MOV TAM_KEY, #5
			MOV N_STATE, #S_LOCKED
			SETB SAFE
			JMP ENCODE_FSM
			
			
			PUT_NUMBERS_ENCRYPT:
				MOV A, INDEX
				DEC A				//visto que depois de fazer, por exemplo, INDEX=0, INC INDEX para futura iteração
				ACALL ENCRYPT_NUMBERS
				MOV @R0, A
				INC R0
				JMP LOOP_STATE_ENCRYPT

//---------------------------------------------FIM Estado STATE_ENCRYPT------------------------------------------------------------------------------	






//---------------------------------------------Inicio Estado STATE_FAIL------------------------------------------------------------------------------	
STATE_FAIL:
	MOV DISPLAY, #0x8E		//Coloca no DISPLAY o 'F'
	MOV MAX_30, #120
	JMP TEST_STATE_FAIL
		
	TEST_STATE_FAIL:
		MOV A, ATTEMPS
		CJNE A, #0, PREP_LOOP_STATE_FAIL
		CLR ET2 			//Desligar Interrupt para o Timer 2
		CLR EA				//Disable Global Interrupt
		CLR TIM_FAIL	
		MOV ATTEMPS, #3
		MOV N_STATE, #S_BLOCKED
		SETB EXAUSTED
		JMP ENCODE_FSM
		
		PREP_LOOP_STATE_FAIL:
			SETB TIM_FAIL 			//Colocar Timer 2 para STATE FAIL
			SETB ET2 				//Ligar Interrupt para o Timer 2
			SETB EA					//Enable Global Interrupt
			JMP LOOP_STATE_FAIL
		
		LOOP_STATE_FAIL:
			JBC TIMEOUT, OPORTUNITY
			JMP LOOP_STATE_FAIL
		
		OPORTUNITY:
			CLR ET2 		//Desligar Interrupt para o Timer 2
			CLR EA			//Desligar Interrupt para o Timer 2
			CLR TIM_FAIL	
			MOV N_STATE, #S_DECRYPT
			MOV INDEX, #0
			JMP ENCODE_FSM

//---------------------------------------------Fim Estado STATE_FAIL------------------------------------------------------------------------------	




//---------------------------------------------Inicio Estado STATE_BLOCKED------------------------------------------------------------------------------	

STATE_BLOCKED:
	MOV DISPLAY, #0x83						//Coloca 'b' no DISPLAY
	SETB TIM_BLOCKED 						//Colocar Timer 2 para STATE BLOCKED
	SETB ET2 								//Ligar Interrupt para o Timer 2
	SETB EA									//Ligar Interrupt para o Timer 2
	SETB FLAG_RECOVER						//Ativar flag responsável pela Recover Condition
	JMP LOOP_STATE_BLOCKED	

	LOOP_STATE_BLOCKED:		
		JMP LOOP_STATE_BLOCKED
		
		
//---------------------------------------------Fim Estado STATE_BLOCKED------------------------------------------------------------------------------	




//---------------------------------------------Inicio Estado STATE_RECOVER------------------------------------------------------------------------------	

STATE_RECOVER:
	MOV INDEX, #0
	MOV DPTR, #ARRAY_DIGITS
	MOV R0, #STORAGE_NUMBERS_RECOVER
	MOV R1, #STORAGE_RECOVER_KEY
	MOV R5, #0
	LCALL SHOW_DIGITS
	JMP LOOP_STATE_RECOVER
	
	LOOP_STATE_RECOVER:
		CJNE R5, #8, LOOP_STATE_RECOVER_CONTINUE
		MOV TAM_REC_KEY, #1
		JMP STATE_RECOVER_LOAD
		
		LOOP_STATE_RECOVER_CONTINUE:
		LCALL LOOP
		JBC SET_PREMIDO, STATE_RECOVER_SET
		JBC LOAD_PREMIDO, STATE_RECOVER_LOAD
	
		STATE_RECOVER_SET:
			LCALL SHOW_DIGITS
			JMP LOOP_STATE_RECOVER
			
		STATE_RECOVER_LOAD:
			INC R5
			DJNZ TAM_REC_KEY, PUT_NUMBER_REC
			MOV R0, #STORAGE_NUMBERS_RECOVER
			MOV A, @R1
			ACALL DECRYPT_NUMBERS
			CLR C
			SUBB A, @R0
			JNZ FALHA_RECOVER		//Se 1ºdigito inserido na fechadura referente à RECOVER_CONDITION != 1ºdigito do código da RECOVER_CONDITION -> FALHA_RECOVER
			INC R0
			INC R1
			MOV A, @R1
			ACALL DECRYPT_NUMBERS
			CLR C
			SUBB A, @R0
			JNZ FALHA_RECOVER		//Se 2ºdigito inserido na fechadura referente à RECOVER_CONDITION != 2ºdigito do código da RECOVER_CONDITION -> FALHA_RECOVER
			INC R0
			INC R1
			MOV A, @R1
			ACALL DECRYPT_NUMBERS
			CLR C
			SUBB A, @R0
			JNZ FALHA_RECOVER		//Se 3ºdigito inserido na fechadura referente à RECOVER_CONDITION != 3ºdigito do código da RECOVER_CONDITION -> FALHA_RECOVER
			INC R0
			INC R1
			MOV A, @R1
			ACALL DECRYPT_NUMBERS
			CLR C
			SUBB A, @R0
			JNZ FALHA_RECOVER		//Se 4ºdigito inserido na fechadura referente à RECOVER_CONDITION != 4ºdigito do código da RECOVER_CONDITION -> FALHA_RECOVER
			INC R0
			INC R1
			MOV A, @R1
			ACALL DECRYPT_NUMBERS
			CLR C
			SUBB A, @R0
			JNZ FALHA_RECOVER		//Se 5ºdigito inserido na fechadura referente à RECOVER_CONDITION != 5ºdigito do código da RECOVER_CONDITION -> FALHA_RECOVER
			INC R0
			INC R1
			MOV A, @R1
			ACALL DECRYPT_NUMBERS
			CLR C
			SUBB A, @R0
			JNZ FALHA_RECOVER		//Se 6ºdigito inserido na fechadura referente à RECOVER_CONDITION != 6ºdigito do código da RECOVER_CONDITION -> FALHA_RECOVER
			INC R0
			INC R1
			MOV A, @R1
			ACALL DECRYPT_NUMBERS
			CLR C
			SUBB A, @R0
			JNZ FALHA_RECOVER		//Se 7ºdigito inserido na fechadura referente à RECOVER_CONDITION != 7ºdigito do código da RECOVER_CONDITION -> FALHA_RECOVER
			INC R0
			INC R1
			MOV A, @R1
			ACALL DECRYPT_NUMBERS
			CLR C
			SUBB A, @R0
			JNZ FALHA_RECOVER		//Se 8ºdigito inserido na fechadura referente à RECOVER_CONDITION != 8ºdigito do código da RECOVER_CONDITION -> FALHA_RECOVER		
			
			CLR FLAG_RECOVER
			SETB SAFE_RECOVER		//SEC_KEY de fábrica
			MOV TAM_REC_KEY, #9
			MOV N_STATE, #S_LOCKED
			JMP ENCODE_FSM
			
			FALHA_RECOVER:
				MOV TAM_REC_KEY, #9
				MOV N_STATE, #S_BLOCKED
				JMP ENCODE_FSM
			
			

			PUT_NUMBER_REC:
				MOV A, INDEX
				DEC A				//visto que já se faz uma iteração no início
				MOV @R0, A
				INC R0
				JMP LOOP_STATE_RECOVER
				
				

//---------------------------------------------Fim Estado STATE_RECOVER------------------------------------------------------------------------------	



//-----------------------------------Subrotina responsável por Escrever na FLASH os números da chave secreta--------------------------------------------------------------------	

WRITE_FLASH:
	MOV DPTR, #0x7A18
	MOV R1, #STORAGE_USER_KEY
	MOV A, @R1
	//CLR FLBWE
	ANL PFE0CN, #00H
	//SETB PSWE
	ORL PSCTL, #1
	//CLR PSEE
	ANL PSCTL, #0FDH
	MOV FLKEY, #0xA5
	MOV FLKEY, #0xF1
	MOVX @DPTR, A
	INC DPTR
	INC R1
	MOV FLKEY, #0xA5
	MOV FLKEY, #0xF1
	MOV A, @R1
	MOVX @DPTR, A
	INC DPTR
	INC R1
	MOV FLKEY, #0xA5
	MOV FLKEY, #0xF1
	MOV A, @R1
	MOVX @DPTR, A
	INC DPTR
	INC R1
	MOV FLKEY, #0xA5
	MOV FLKEY, #0xF1
	MOV A, @R1
	MOVX @DPTR, A
	//CLR PSWE
	ANL PSCTL, #0FEH
	RET

//-----------------------------------Subrotina responsável por Escrever na FLASH os números da chave secreta--------------------------------------------------------------------	






//--------------------------------------------------Subrotina responsável por Apagar a página na FLASH -------------------------------------------------------------------------	
ERASE_FLASH:
	MOV DPTR, #0x7A18
	MOV A, #7
	MOV FLKEY, #0xA5
	MOV FLKEY, #0xF1
	//SETB PSEE 
	ORL PSCTL, #2
	//SETB PSWE
	ORL PSCTL, #1
	MOVX @DPTR, A
	//CLR PSWE
	ANL PSCTL, #0FEH
	//CLR PSEE
	ANL PSCTL, #0FDH
	RET

//--------------------------------------------------Subrotina responsável por Apagar a página na FLASH -------------------------------------------------------------------------	




//------------------------------------------Subrotina responsável por Ler da FLASH os números da chave secreta -----------------------------------------------------------------	
READ_FLASH:
	MOV A, INDEX
	MOVC A, @A + DPTR
	RET
	
//------------------------------------------Subrotina responsável por Ler da FLASH os números da chave secreta -----------------------------------------------------------------	





//-----------------------------------Subrotina responsável por Escrever na FLASH a flag responsável por validar o código--------------------------------------------------------	
WRITE_FLASH_FLAG:
	MOV DPTR, #0x7A1C
	MOV A, #13
	//CLR FLBWE
	ANL PFE0CN, #00H
	//SETB PSWE
	ORL PSCTL, #1
	//CLR PSEE
	ANL PSCTL, #0FDH
	MOV FLKEY, #0xA5
	MOV FLKEY, #0xF1
	MOVX @DPTR, A
	//CLR PSWE
	ANL PSCTL, #0FEH
	RET
//-----------------------------------Subrotina responsável por Escrever na FLASH a flag responsável por validar o código--------------------------------------------------------	




//-----------------------------------Subrotina responsável por Ler da FLASH a flag responsável por validar o código--------------------------------------------------------	
READ_FLASH_FLAG:
	MOV DPTR, #0x7A1C
	MOV A, #0
	MOVC A, @A + DPTR
	RET
//-----------------------------------Subrotina responsável por Ler da FLASH a flag responsável por validar o código--------------------------------------------------------	




//-----------------------------------Subrotina responsável por Escrever na FLASH os números da chave secreta--------------------------------------------------------------------	

		
//-----------------------------------Subrotina responsável por ENCRIPTAR os números da chave secreta--------------------------------------------------------------------	
ENCRYPT_NUMBERS:
	RL A
	CLR C
	ADD A, #10
	RET
//-----------------------------------Subrotina responsável por ENCRIPTAR os números da chave secreta--------------------------------------------------------------------	




//-----------------------------------Subrotina responsável por DESENCRIPTAR os números da chave secreta--------------------------------------------------------------------	
DECRYPT_NUMBERS:
	CLR C
	SUBB A, #10
	RR A
	RET
//-----------------------------------Subrotina responsável por DESENCRIPTAR os números da chave secreta--------------------------------------------------------------------	




//------------------------------------LOOP responsável para verificar se K_SET ou K_LOAD foram premidos-----------------------------------------------------------------
LOOP:
	JNB K_SET, K_SETPRESSED																				//K_SETPRESSED se K_SET estiver a 0 'P0.6 pressionado'
	JNB K_LOAD, K_LOADPRESSED																			//K_LOADPRESSED se K_LOAD estiver a 0 'P0.7 pressionado'
	JMP LOOP
		
K_SETPRESSED:
	JNB K_SET, $																						//Enquanto não for desprimido:
	SETB SET_PREMIDO																					//Coloca a '1' SET_PREMIDO
	RET

K_LOADPRESSED:
	JNB K_LOAD, $																						//Enquanto não for desprimido
	SETB LOAD_PREMIDO																					//Coloca a '1' LOAD_PRESSED
	RET
//------------------------------------LOOP responsável para verificar se K_SET ou K_LOAD foram premidos-----------------------------------------------------------------




//-----------------------------------Subrotina responsável por colocar RECOVER_KEY--------------------------------------------------------------------

PUT_RECOVER_KEY:
	MOV R1, #STORAGE_RECOVER_KEY	
	MOV A, #2
	ACALL ENCRYPT_NUMBERS
	MOV @R1, A
	INC R1
	MOV A, #0
	ACALL ENCRYPT_NUMBERS
	MOV @R1, A
	INC R1
	MOV A, #2
	ACALL ENCRYPT_NUMBERS
	MOV @R1, A
	INC R1
	MOV A, #0
	ACALL ENCRYPT_NUMBERS
	MOV @R1, A
	INC R1
	MOV A, #2
	ACALL ENCRYPT_NUMBERS
	MOV @R1, A
	INC R1
	MOV A, #0
	ACALL ENCRYPT_NUMBERS
	MOV @R1, A
	INC R1
	MOV A, #2
	ACALL ENCRYPT_NUMBERS
	MOV @R1, A
	INC R1
	MOV A, #1
	ACALL ENCRYPT_NUMBERS
	MOV @R1, A
	RET
	
//-----------------------------------Subrotina responsável por colocar RECOVER_KEY--------------------------------------------------------------------




//-----------------------------------Subrotina responsável por fazer o update dos números no DISPLAY--------------------------------------------------------------------
SHOW_DIGITS:
	MOV A, INDEX
	CJNE A, #10, LABEL_AUX
	MOV INDEX, #0
	MOV A, INDEX																						//Move para o acumulador 'A' a variavel 'INDEX'
	MOVC A, @A + DPTR																					//Move para o acumulador 'A' o conteúdo apontado por '@A + DPTR'
																											//Se premir 1x P0.6 -> A = 0 + DPTR = conteúdo do indíce 1 do array -> 0C0H 
																											//Se premir 2x P0.6 -> A = 1 + DPTR = conteúdo do indice 2 do array -> 0F9H 
	MOV DISPLAY, A																						//Colocar no DISPLAY *porta P2*, o acumulador 'A'
	INC INDEX																							//Incrementa 1 à variavél 'INDEX'
	RET	

	LABEL_AUX:
		MOV A, INDEX																						//Move para o acumulador 'A' a variavel 'INDEX'
		MOVC A, @A + DPTR																					//Move para o acumulador 'A' o conteúdo apontado por '@A + DPTR'
																												//Se premir 1x P0.6 -> A = 0 + DPTR = conteúdo do indíce 1 do array -> 0C0H 
																												//Se premir 2x P0.6 -> A = 1 + DPTR = conteúdo do indice 2 do array -> 0F9H 
		MOV DISPLAY, A																						//Colocar no DISPLAY *porta P2*, o acumulador 'A'
		INC INDEX																							//Incrementa 1 à variavél 'INDEX'
		RET	
//-----------------------------------Subrotina responsável por fazer o update dos números no DISPLAY--------------------------------------------------------------------	



	
//-----------------------------------Subrotina responsável por definir as configurações para o Timer 2--------------------------------------------------------------------		
TIMER2_INIT:
	MOV TMR2CN, #4H									//Timer 2: 16 bit c/auto-reload
	MOV TMR2L, #LOW(-1)
    MOV TMR2H, #HIGH(-1)
	MOV TMR2RLL, #LOW(-40000)
    MOV TMR2RLH, #HIGH(-40000)
    RET
//-----------------------------------Subrotina responsável por definir as configurações para o Timer 2--------------------------------------------------------------------		



//-----------------------------------Subrotina responsável por definir as configurações para o SYSCLK--------------------------------------------------------------------		
OSCILATOR_INIT:
    MOV FLSCL, #090h
    MOV CLKSEL, #003h
    RET
//-----------------------------------Subrotina responsável por definir as configurações para o SYSCLK--------------------------------------------------------------------		



//-----------------------------------Subrotina responsável por definir as configurações--------------------------------------------------------------------	   
CONFIGS:
	MOV PCA0MD, #0H																						//Desabilitar o WatchDod Timer
	MOV XBR1, #40H																						//Ativar a Crossbar -> para o Display de 7 segmentos e P0.6 e P0.7 funcionar -> 'ligar pinos físicos/metálicos
	RET
//-----------------------------------Subrotina responsável por definir as configurações--------------------------------------------------------------------

END