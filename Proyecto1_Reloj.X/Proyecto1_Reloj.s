 ; Archivo:	  main.s  
 ; Dispositivo:	  PIC16F887
 ; Autor:	  Javier López
 ; Compilador:	  pic-as (v2.30), MPLAB V5.50
 ; 
 ; Programa:	  Reloj digital programable con displays de 7 segmentos
 ; Harware:	  Display de 7 segmentos multiplexado a 4 dígitos en puerto a,
 ;		  push buttons en puerto b, leds de estado en puerto c, 
 ;		  transistores npn con resistencias pull-up en puerto d,
 ;		  conexión DP del display de 7 segmentos en puerto e
 ; 
 ; Creado: 13 septiembre, 2021
 ; Última modificación: 21 septiembre, 2021
  
 PROCESSOR 16F887
 #include <xc.inc>
 
 ;configuration word 1
 CONFIG FOSC=INTRC_NOCLKOUT // Oscillador Interno sin salidas
 CONFIG WDTE=OFF	    // WDT disabled (reinicio repetitivo del pic)
 CONFIG PWRTE=OFF	    // PWRT enabled (espera de 72ms al iniciar)
 CONFIG MCLRE=OFF	    // El pin de MCLR se utiliza como I/O
 CONFIG CP=OFF		    // Sin protección de código
 CONFIG CPD=OFF		    // Sin protección de datos
 
 CONFIG BOREN=OFF   // Sin reinicio cuando el voltaje de alimentación baja de 4V
 CONFIG IESO=OFF    // Reinicio sin cambio de reloj de interno a externo
 CONFIG FCMEN=OFF   // Cambio de reloj externo a interno en caso de fallo
 CONFIG LVP=OFF	    // programación en bajo voltaje permitida
 
 ;configuration word 2
 CONFIG WRT=OFF		// Protección de autoescritura por el programa desactivada
 CONFIG BOR4V=BOR40V	// Reinicio abajo de 4V, (BOR21V=2.1V)
 
 //============================================================================
 //================================== MACROS ==================================
 //============================================================================
 
 //=============================== RESET TMR0 =================================
 restart_tmr0 macro
    banksel PORTA
    movlw   231		    // valor inicial para obtener saltos de 2ms
    movwf   TMR0	    // almacenar valor inicial en TMR0
    bcf	    T0IF	    // limpiar bandera de overflow
    endm
 //=============================== RESET TMR1 =================================
 restart_tmr1 macro
    movlw   0xB		    // ingresar valor de 1seg, (0x0BDC) a TMR1
    movwf   TMR1H
    movlw   0xDC
    movwf   TMR1L  
    bcf	    TMR1IF	    // limpiar bandera de overflow
    endm
 //================================= DIVISOR ==================================
 wdivl	macro	divisor, cociente, residuo
    movwf   aux_div
    clrf    aux_div+1
    incf    aux_div+1
    movlw   divisor
    subwf   aux_div, f
    btfsc   STATUS,0
    goto    $-4
    decf    aux_div+1, w
    movwf   cociente
    movlw   divisor
    addwf   aux_div, w
    movwf   residuo	
    endm
    
 //============================================================================
 //============================= VARIABLES ====================================
 //============================================================================
 PSECT udata_bank0 // common memory
    switch:	    DS  1	// switch de estado de los transistores
    switch_rb:	    DS	1	// switch de estado de los botones
    aux_div:	    DS  2	// variable auxiliar del macro divisor
    aux_dias:	    DS	1	// variable aux para limitar los días del mes
    aux_febrero:    DS	2	// variable aux para limitar febrero
    
    segundos:	    DS  1	// Variables acumuladoras de tiempo
    minutos:	    DS  1
    horas:	    DS  1
    dias:	    DS  1
    meses:	    DS  1
    
    minutos_d1:	    DS  1	// Variables que reciben los resultados de las
    minutos_d2:	    DS  1	// divisiones
    horas_d3:	    DS  1
    horas_d4:	    DS  1
    
    meses_d1:	    DS  1	// Más variables que reciben los resultados de
    meses_d2:	    DS  1	// las divisiones
    dias_d3:	    DS  1	 
    dias_d4:	    DS  1	
    
    mostrar_d1:	    DS  1	// variables que almacenan el valor que se
    mostrar_d2:	    DS  1	// mostrará en los displays ya convertido
    mostrar_d3:	    DS  1	// por una tabla
    mostrar_d4:	    DS  1

 PSECT udata_shr // common memory
    W_TEMP:	    DS  1	; 1 byte
    STATUS_TEMP:    DS  1	; 1 byte
  
 //============================================================================   
 //================================== RESET ===================================
 //============================================================================
 PSECT resVect, class=CODE, abs, delta=2
 ORG 00h	// posición 0000h para el reset
 resetVec:
     PAGESEL main
     goto main
     
 //============================================================================  
 //=========================== VECTOR INTERRUCPIÓN ============================  
 //============================================================================
 PSECT intVect, class=CODE, abs, delta=2
 ORG 04h			// posición 0004h para interrupciones
 push:
    movwf	W_TEMP
    swapf	STATUS, W
    movwf	STATUS_TEMP
 isr:
    btfsc	T0IF		// chequear bandera de tmr0
    call	int_t0
    btfsc	TMR1IF		// chequear bandera de tmr1
    call	int_t1
    btfsc	TMR2IF		// chequear bandera de tmr2
    call	int_t2
    btfsc	RBIF		// chequear bandera de rbif
    call	int_iocb
 pop1:
    swapf	STATUS_TEMP, W
    movwf	STATUS
    swapf	W_TEMP, F
    swapf	W_TEMP, W
    retfie
    
 //============================================================================   
 //====================== SUBRUTINAS DE INTERRUPCIÓN ==========================
 //============================================================================
 
 //=========================== SUBRUTINAS DE TMR0 =============================
 int_t0:
    restart_tmr0		// bajar bandera y reestablecer su valor
    clrf	PORTD		// apagar cualquier transistor encendido
    
    btfss	switch,1	// cascada de comparaciones para determinar en 
    goto	estado_0x_t0	// cual de los 4 estados se encuentra el switch
    goto	estado_1x_t0	// y así determinar cual transistor encender
 estado_0x_t0:
    btfss	switch,0
    goto	estado_00_t0
    goto	estado_01_t0
 estado_1x_t0:
    btfss	switch,0
    goto	estado_10_t0
    goto	estado_11_t0
    
 estado_00_t0:
    incf	switch		// incrementar switch
    movf	mostrar_d1,w	// mover el valor a mostrar a w
    movwf	PORTA		// mover w a puerto a
    bsf		PORTD,4		// encender el transistor correspondiente
    goto	return_t0
 estado_01_t0:
    incf	switch		// incrementar switch
    movf	mostrar_d2,w	// mover el valor a mostrar a w
    movwf	PORTA		// mover w a puerto a
    bsf		PORTD,5		// encender el transistor correspondiente
    goto	return_t0
 estado_10_t0:
    incf	switch		// incrementar switch
    movf	mostrar_d3,w	// mover el valor a mostrar a w
    movwf	PORTA		// mover w a puerto a
    bsf		PORTD,6		// encender el transistor correspondiente
    goto	return_t0
 estado_11_t0:
    clrf	switch		// limpiar switch
    movf	mostrar_d4,w	// mover el valor a mostrar a w
    movwf	PORTA		// mover w a puerto a
    bsf		PORTD,7		// encender el transistor correspondiente
    goto	return_t0
 return_t0:
    return
 //========================= SUBRUTINAS DE TMR1 ===============================
 int_t1:
    restart_tmr1
    incf	segundos	// incrementar variable que cuenta segundos
    return
 //============================ SUBRUTINAS DE TMR2 ============================
 int_t2:
    bcf		TMR2IF
    incf	PORTE		// incrementar puerto e para hacer titilar cada	
    return			// 500ms una led
 //========================== SUBRUTINAS DE PORTB =============================
 int_iocb:
    banksel	PORTB
    clrf	PORTC		// limpiar leds de estado
    
    btfss	PORTB,4		// salta si el pull-up sigue activo
    incf	switch_rb	// cambiar de estado cada vez que se presione el botón
    
    btfss	switch_rb,1	// cascada de comparaciones para determinar en 
    goto	estado_0x_rb	// cual de los 4 estados se encuentra el switch_rb
    goto	estado_1x_rb	// y así determinar que acciones realizan los botones
 estado_0x_rb:
    btfss	switch_rb,0
    goto	estado_00_rb
    goto	estado_01_rb
 estado_1x_rb:
    btfss	switch_rb,0
    goto	estado_10_rb
    goto	estado_11_rb
    
 estado_00_rb:			// estado de lectura de hora
    // los demás botones son inútiles en este estado, así que no se hace nada
    bcf		RBIF
    return
 estado_01_rb:			// estado de lectura de fecha
    bsf		PORTC,6
    // los demás botones son inútiles en este estado, así que no se hace nada
    bcf		RBIF
    return
 estado_10_rb:			// estado de escritura de hora
    bsf		PORTC,7
    btfss	PORTB,0		
    incf	minutos		// incrementar minutos
    btfss	PORTB,1		
    decf	minutos		// decrementar minutos
    btfss	PORTB,2		
    incf	horas		// incrementar horas
    btfss	PORTB,3		
    decf	horas		// decrementar horas
    bcf		RBIF
    return
 estado_11_rb:			// estado de escritura de hora
    bsf		PORTC,6
    bsf		PORTC,7
    btfss	PORTB,0		
    incf	dias		// incrementar dias
    btfss	PORTB,1		
    decf	dias		// decrementar dias
    btfss	PORTB,2		
    incf	meses		// incrementar meses
    btfss	PORTB,3		
    decf	meses		// decrementar meses
    bcf		RBIF
    return
 //============================================================================
 PSECT code, delta=2, abs
 ORG 100h	    // posición 0100h para tabla
 //============================================================================
 //================================== TABLAS ==================================
 //============================================================================
 tabla:
    clrf    PCLATH
    bsf	    PCLATH, 0	// PCLATH = 01	PCL = 02
    addwf   PCL		// PC = PCLATH + PCL + w
    retlw   00111111B	// 0
    retlw   00000110B	// 1
    retlw   01011011B	// 2
    retlw   01001111B	// 3
    retlw   01100110B	// 4
    retlw   01101101B	// 5
    retlw   01111101B	// 6
    retlw   00000111B	// 7
    retlw   01111111B	// 8
    retlw   01101111B	// 9
    retlw   00111111B	// 0 (Posición extra para evitar errores)
 
 //============================================================================
 PSECT code, delta=2, abs
 ORG 130h	    // posición 0130h para tabla
 //============================================================================
 tabla_meses:
    clrf    PCLATH
    bsf	    PCLATH, 0	// PCLATH = 01	PCL = 02
    addwf   PCL		// PC = PCLATH + PCL + w
    retlw   32	// (Posición extra para evitar errores)
    retlw   32	// enero
    retlw   29	// febrero
    retlw   32	// marzo
    retlw   31	// abril
    retlw   32	// mayo
    retlw   31	// junio
    retlw   32	// julio
    retlw   32	// agosto
    retlw   31	// septiembre
    retlw   32	// octubre
    retlw   31	// noviembre
    retlw   32	// diciembre
    retlw   32	// (Posición extra para evitar errores)
 //============================================================================
 //================================== CÓDIGO ==================================
 //============================================================================
 
 
 //==================================  MAIN  ==================================
 main:
    call	config_io
    call	config_reloj
    call	config_tmr0
    call	config_tmr1
    call	config_tmr2
    call	config_int_enable
    call	config_pullups
    call	config_iocb 
    banksel	PORTA
 //============================= LOOP PRINCIPAL ===============================
 loop:
    call	inc_minutos	// llamar a todos los incrementos en tiempo
    call	inc_horas
    call	inc_dias
    call	inc_meses
    
    call	limites		// llamar a los límites que siguen las variables incrementadas
    
    call	fms		// llamar a la máquina de estados finitos
    
    goto	loop
 //============================================================================   
 //=============================== SUBRUTINAS =================================
 //============================================================================
 
 
 //============================ ENTRADAS Y SALIDAS ============================
 config_io:
    banksel	ANSEL
    clrf	ANSEL
    clrf	ANSELH	    // pines digitales
    
    banksel	TRISA
    clrf	TRISA	    // puerto a como salida (displays multiplexados) 
    bsf		TRISB,0
    bsf		TRISB,1
    bsf		TRISB,2
    bsf		TRISB,3
    bsf		TRISB,4	    // puerto b como entrada (botones)
    bcf		TRISC,6	    // puerto c como salida (leds de estado)
    bcf		TRISC,7
    bcf		TRISD,4	    // puerto d como salida (transistores)
    bcf		TRISD,5
    bcf		TRISD,6
    bcf		TRISD,7
    bcf		TRISE,0	    // puerto e como salida (DP del display)
    
    banksel	PORTA
    clrf	PORTA	    // limpiar puerto a
    clrf	PORTC	    // limpiar puerto c
    clrf	PORTD	    // limpiar puerto d
    clrf	PORTE	    // limpiar puerto e
    
    clrf	mostrar_d1
    clrf	mostrar_d2
    clrf	mostrar_d3
    clrf	mostrar_d4  // limpiar variables de display
    
    clrf	switch
    clrf	switch_rb   // limpiar variables de estado
    
    clrf	segundos    // limpiar variables acumuladoras y asignar valores
    clrf	minutos	    // iniciales donde es necesario
    clrf	horas
    clrf	dias
    bsf		dias,0
    clrf	meses	    
    bsf		meses,0
    movlw	2
    movwf	aux_febrero
    return
 //============================== CONFIG RELOJ ================================
 config_reloj:		    // configurar velocidad de oscilador
    banksel	OSCCON
    bcf		IRCF2
    bsf		IRCF1
    bsf		IRCF0	    // reloj a 500kHz (011)
    bsf		SCS	    // reloj interno
    return
 //============================= CONFIG TMR0 ==================================
 config_tmr0:
    banksel	OPTION_REG
    bcf		T0CS	    // reloj interno
    bcf		PSA	    // prescaler a tmr0
    bcf		PS2
    bcf		PS1
    bcf		PS0	    // prescaler a 1:2 (000)
    restart_tmr0	    // llamar a macro de reinicio y preload
    return
 //=============================== CONFIG TMR1 ================================
 config_tmr1:
    banksel	T1CON
    bcf		TMR1GE	    // timer1 siempre contando
    bcf		T1CKPS1
    bsf		T1CKPS0	    // prescaler 1:2
    bcf		T1OSCEN	    // oscilador LP apagado
    bcf		TMR1CS	    // reloj interno
    bsf		TMR1ON	    // reloj encendido
    restart_tmr1	    // llamar a macro de reinicio y preload
    return
 //============================== CONFIG TMR2 =================================
 config_tmr2:		    
    banksel	PORTA
    bsf		TMR2ON	    // activar timer2
    bsf		TOUTPS3
    bsf		TOUTPS2
    bsf		TOUTPS1
    bsf		TOUTPS0	    // postscaler 1:16
    bsf		T2CKPS1
    bcf		T2CKPS0	    // prescaler 16
    banksel	TRISA
    movlw	244	    // 244 de preload para 0.4997s
    movwf	PR2
    clrf	TMR2	    // limpiar timer2
    bcf		TMR2IF	    // limpiar bandera de overflow
    return
 //========================== CONFIG INTERRUPCIONES ===========================
 config_int_enable:
    banksel	TRISA
    bsf		TMR1IE	    // interrupcion del timer1 activada
    bsf		TMR2IE	    // interrupcion del timer2 activada
    banksel	T1CON
    bsf		GIE	    // interrupciones globales activadas
    bsf		PEIE	    // interrupciones periféricas activadas
    bsf		RBIE	    // interrupcion del puerto b activada
    bsf		T0IE	    // interrupcion del timer0 activada
    bcf		T0IF	    // limpiar bandera de overflow de timer0
    bcf		TMR1IF	    // limpiar bandera de overflow de timer1
    bcf		TMR2IF	    // limpiar bandera de overflow de timer2
    bcf		RBIF	    // limpiar bandera de overflow de puerto b
    return
 //============================== CONFIG DE PORTB =============================
 config_pullups:
    banksel	WPUB
    bcf		OPTION_REG, 7	// activar pull-ups (RBPU)
    bsf		WPUB,0
    bsf		WPUB,1
    bsf		WPUB,2
    bsf		WPUB,3
    bsf		WPUB,4		// activar los weak pullups del puerto b
    bcf		WPUB,5
    bcf		WPUB,6
    bcf		WPUB,7		// apagar los innecesarios
    return
 config_iocb:
    banksel	IOCB
    bsf		IOCB,0
    bsf		IOCB,1
    bsf		IOCB,2
    bsf		IOCB,3
    bsf		IOCB,4		// activar interrupt on change del puerto b
    banksel	PORTA
    movf	PORTB, W	// leer puerto b y limpiar bandera para 
    bcf		RBIF		// terminar mismatch
    return
 //=========================== FMS PRINCIPAL (IOCB) ===========================
 fms:
    btfss	switch_rb,1	// cascada de comparaciones para determinar en 
    goto	estado_0x	// cual de los 4 estados se encuentra el switch_rb,
    goto	estado_1x	// mismo switch de la interrupción iocb
 estado_0x:
    btfss	switch_rb,0
    goto	estado_00
    goto	estado_01
 estado_1x:
    btfss	switch_rb,0
    goto	estado_10
    goto	estado_11
    
 estado_00:
    call	divisores_tiempo
    return
 estado_01:
    call	divisores_fecha
    return
 estado_10:
    call	divisores_tiempo
    return
 estado_11:
    call	divisores_fecha
    return
 //======================== PREPARAR DISPLAYS (TMR0) ==========================
 divisores_tiempo:
    movf	minutos, w
    wdivl	10, minutos_d2, minutos_d1  // división de minutos
    call	prep_displays_minutos
    
    movf	horas, w
    wdivl	10, horas_d4, horas_d3	    // división de horas
    call	prep_displays_horas
    return
 prep_displays_minutos:
    movf	minutos_d1, w	// mover a w
    call	tabla		// convertir valor con la tabla
    movwf	mostrar_d1	// pasar a registro que se usará en interrup
    
    movf	minutos_d2, w	// mover a w
    call	tabla		// convertir valor con la tabla
    movwf	mostrar_d2	// pasar a registro que se usará en interrup
    return
 prep_displays_horas:
    movf	horas_d3, w	// mover a w
    call	tabla		// convertir valor con la tabla
    movwf	mostrar_d3	// pasar a registro que se usará en interrup
    
    movf	horas_d4, w	// mover a w
    call	tabla		// convertir valor con la tabla
    movwf	mostrar_d4	// pasar a registro que se usará en interrup
    return
 //============================================================================
  divisores_fecha:
    movf	dias, w
    wdivl	10, dias_d4, dias_d3	    // división de minutos
    call	prep_displays_dias
    
    movf	meses, w
    wdivl	10, meses_d2, meses_d1	    // división de horas
    call	prep_displays_meses
    return
 prep_displays_dias:
    movf	dias_d3, w	// mover a w
    call	tabla		// convertir valor con la tabla
    movwf	mostrar_d3	// pasar a registro que se usará en interrup
    
    movf	dias_d4, w	// mover a w
    call	tabla		// convertir valor con la tabla
    movwf	mostrar_d4	// pasar a registro que se usará en interrup
    return
 prep_displays_meses:
    movf	meses_d1, w	// mover a w
    call	tabla		// convertir valor con la tabla
    movwf	mostrar_d1	// pasar a registro que se usará en interrup
    
    movf	meses_d2, w	// mover a w
    call	tabla		// convertir valor con la tabla
    movwf	mostrar_d2	// pasar a registro que se usará en interrup
    return
 //======================= SUBRUTINAS DE LA HORA (TMR1) =======================   
 inc_minutos:
    movlw	60
    subwf	segundos, w
    btfss	STATUS,2	// saltar si el resultado de la resta es 0
    goto	return_t1	// SALIR DE SUBRUTINA
    clrf	segundos	// resetear cuenta de segundos
    incf	minutos		// incrementar minutos al llegara a 60 segundos
    return
 inc_horas:
    movlw	60
    subwf	minutos, w
    btfss	STATUS,2	// saltar si el resultado de la resta es 0
    goto	return_t1	// SALIR DE SUBRUTINA
    clrf	minutos		// resetear cuenta de minutos
    incf	horas		// incrementar minutos al llegara a 60 segundos
    return
 inc_dias:
    movlw	24
    subwf	horas, w
    btfss	STATUS,2	// saltar si el resultado de la resta es 0
    goto	return_t1	// SALIR DE SUBRUTINA
    clrf	horas		// resetear cuenta de horas
    incf	dias		// incrementar minutos al llegara a 60 segundos
    return
 inc_meses:
    movf	meses, w	// mover el valor de mes actual a w
    call	tabla_meses	// mover el límite de días del mes actual a w
    subwf	dias, w		// restar el valor límite con el número actual
    btfss	STATUS,2	// saltar si el resultado de la resta es 0
    goto	return_t1
    clrf	dias		// si se alcanzó el límite, reiniciar cuenta de días
    bsf		dias,0		// setear dias en 1 como valor inicial
    incf	meses		// e incrementar el valor de meses
    return
 return_t1:
    return
 //========================== SUBRUTINAS DE LÍMITES ===========================
 limites:
    call	limite_minutos
    call	limite_horas
    call	limite_inf_dias
    call	limite_inf_meses
    call	limite_sup_meses
    call	limite_febrero_1
    call	limite_febrero_2
    return
 limite_minutos:
    btfss	minutos,7	// chequear el bit más significativo
    goto	return_limites
    bcf		minutos,7
    bcf		minutos,6
    bsf		minutos,5
    bsf		minutos,4
    bsf		minutos,3
    bcf		minutos,2
    bsf		minutos,1
    bsf		minutos,0	// actualizar al valor a .59 -> 00111011B
    return
 limite_horas:
    btfss	horas,7		// revisar el bit más significativo
    goto	return_limites
    bcf		horas,7
    bcf		horas,6
    bcf		horas,5
    bsf		horas,4
    bcf		horas,3
    bsf		horas,2
    bsf		horas,1
    bsf		horas,0		// actualizar al valor a .23 -> 00010111B
    return
 limite_inf_dias:		// incrementar de 0 a 1 automáticamente
    btfsc	dias,7		// revisar que cada bit sea 0
    goto	return_limites
    btfsc	dias,6
    goto	return_limites
    btfsc	dias,5
    goto	return_limites
    btfsc	dias,4
    goto	return_limites
    btfsc	dias,3
    goto	return_limites
    btfsc	dias,2
    goto	return_limites
    btfsc	dias,1
    goto	return_limites
    btfsc	dias,0
    goto	return_limites
    
    movf	meses,w		// mover meses a w
    call	tabla_meses	// obtener el número de días que tiene el mes
    movwf	aux_dias	// mover este número a variable auxiliar
    decf	aux_dias	// reducir en uno, para ajustarse al último día hábil
    movf	aux_dias,w	// mover el valor del auxiliar a w
    movwf	dias		// mover w a dias
    return
 limite_inf_meses:		// incrementar de 0 a 12 automáticamente
    btfsc	meses,7		// revisar que cada bit sea 0
    goto	return_limites
    btfsc	meses,6
    goto	return_limites
    btfsc	meses,5
    goto	return_limites
    btfsc	meses,4
    goto	return_limites
    btfsc	meses,3
    goto	return_limites
    btfsc	meses,2
    goto	return_limites
    btfsc	meses,1
    goto	return_limites
    btfsc	meses,0
    goto	return_limites
    
    movlw	12		// mover el valor de meses a 12
    movwf	meses
    return
 limite_sup_meses:		// limitar a 12 los meses
    btfsc	meses,7		// revisar cada bit para 13 (0000 1101)
    goto	return_limites
    btfsc	meses,6
    goto	return_limites
    btfsc	meses,5
    goto	return_limites
    btfsc	meses,4
    goto	return_limites
    btfss	meses,3
    goto	return_limites
    btfss	meses,2
    goto	return_limites
    btfsc	meses,1
    goto	return_limites
    btfss	meses,0
    goto	return_limites
    
    clrf	meses		// valor de meses a 0
    bsf		meses,0		// aumentar meses a 1
    return
 limite_febrero_1:
    movf	meses,w
    subwf	aux_febrero,w	// and entre meses y 2 para ver si es febrero
    btfss	STATUS,2	// saltar si el mes es febrero
    goto	return_limites
    
    btfsc	dias,7		// revisar cada bit para 31 (0001 1111)
    goto	return_limites
    btfsc	dias,6
    goto	return_limites
    btfsc	dias,5
    goto	return_limites
    btfss	dias,4
    goto	return_limites
    btfss	dias,3
    goto	return_limites
    btfss	dias,2
    goto	return_limites
    btfss	dias,1
    goto	return_limites
    btfss	dias,0
    goto	return_limites
    
    clrf	dias		// hacer que regrese a 28
    return
 limite_febrero_2:
    movf	meses,w
    subwf	aux_febrero,w	// and entre meses y 2 para ver si es febrero
    btfss	STATUS,2	// saltar si el mes es febrero
    goto	return_limites
    
    btfsc	dias,7		// revisar cada bit para 30 (0001 1110)
    goto	return_limites
    btfsc	dias,6
    goto	return_limites
    btfsc	dias,5
    goto	return_limites
    btfss	dias,4
    goto	return_limites
    btfss	dias,3
    goto	return_limites
    btfss	dias,2
    goto	return_limites
    btfss	dias,1
    goto	return_limites
    btfsc	dias,0
    goto	return_limites
    
    clrf	dias		// hacer que regrese a 28
    return
 return_limites:
    return
 //============================================================================
 END