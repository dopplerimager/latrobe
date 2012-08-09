
;\\ CLEANUP ROUTINES
pro LaTrobe_cleanup, misc, console

	;\\ Close up the com ports
	comms_wrapper, misc.port_map.cal_source.number, misc.dll_name, type = 'moxa', /close, errcode=errcode
	console->log, 'Close Calibration Source Port: ' + string(errcode, f='(i0)'), 'InstrumentSpecific'
	comms_wrapper, misc.port_map.mirror.number, misc.dll_name, type = 'moxa', /close, errcode=res1
	console->log, 'Close Mirror Port: ' + string(errcode, f='(i0)'), 'InstrumentSpecific'
	comms_wrapper, misc.port_map.etalon.number, misc.dll_name, type = 'moxa', /close, errcode=res2
	console->log, 'Close Etalon Port: ' + string(errcode, f='(i0)'), 'InstrumentSpecific'

	;\\ Sometimes the ports won't close properly, so use the devcon utility to restart the Moxa device
	if res1 ne 0 or res2 ne 0 then begin
		restart_moxa
	endif

end





;\\ MOTOR ROUTINES
pro LaTrobe_mirror, drive_to_pos = drive_to_pos, $
				  home_motor = home_motor, $
				  read_pos = read_pos, $
				  misc, console

	;\\ Stop the camera while we move the mirror:
	   	res = call_external(misc.dll_name, 'uAbortAcquisition')


	;\\ Misc stuff
		port = misc.port_map.mirror.number
		dll_name = misc.dll_name
		tx = string(13B)

	;\\ Set current limits
		comms_wrapper, port, dll_name, type='moxa', /write, data = 'LCC900'  + tx ;\\ set these here to be safe...
		comms_wrapper, port, dll_name, type='moxa', /write, data = 'LPC1200' + tx

	;\\ Drive to sky or cal position:
		if keyword_set(drive_to_pos) then begin
			;\\ Notify that we are changing the mirror position
				base = widget_base(col=1, group=misc.console_id, /floating)
				info = widget_label(base, value='Driving Mirror to ' + string(drive_to_pos, f='(i0)'), font='Ariel*20*Bold')
				widget_control, /realize, base

				res = drive_motor(port, dll_name, drive_to = drive_to_pos, speed = 1000)
				read_pos = drive_motor(port, dll_name, /readpos)

			;\\ Close notification window
				if widget_info(base, /valid) eq 1 then widget_control, base, /destroy
		endif


	;\\ Home to the sky or calibration positions
		if keyword_set(home_motor) then begin

			;\\ Notify that we are homing the mirror
				base = widget_base(col=1, group=misc.console_id, /floating)
				info = widget_label(base, value='Homing Mirror to ' + home_motor, font='Ariel*20*Bold')
				widget_control, /realize, base

		    if strlowcase(home_motor) eq 'sky' then direction = 'forwards'
		    if strlowcase(home_motor) eq 'cal' then direction = 'backwards'

			ntries = 0
			GO_HOME_MOTOR_START:

				pos1 = drive_motor(port, dll_name, /readpos)
				res  = drive_motor(port, dll_name, direction = direction, speed = 450., home_max_spin_time = 3.)
				pos2 = drive_motor(port, dll_name, /readpos)
				ntries = ntries + 1

			if abs(pos2 - pos1)/1000. gt .3 or ntries lt 2 then goto, GO_HOME_MOTOR_START
			read_pos = drive_motor(port, dll_name, /readpos)

			if strlowcase(home_motor) eq 'cal' then	begin
				comms_wrapper, port, dll_name, type='moxa', /write, data = 'HO'  + tx
				res = drive_motor(port, dll_name, drive_to = read_pos + 1000)
			endif else begin
				res = drive_motor(port, dll_name, drive_to = read_pos - 3000)
			endelse

			;\\ Close notification window
				if widget_info(base, /valid) eq 1 then widget_control, base, /destroy
		endif

	read_pos = drive_motor(port, dll_name, /readpos)

	;\\ Restart the camera
		res = call_external(misc.dll_name, 'uStartAcquisition')

end




;\\ CALIBRATION SWITCH ROUTINES
pro LaTrobe_switch, source, $
				    misc, $
				    console, $
				    home=home

	case source of
		0: motor_pos = -950 ;\\ fs laser, at full strength
		4: motor_pos = -870 ;\\ fs laser, offset to attenuate the light (hole is at -950)
		1: motor_pos = -1700
		2: motor_pos = -2450
		3: motor_pos = -200	;\\ neon
		else:
	endcase

	port = misc.port_map.cal_source.number
	dll_name = misc.dll_name
	tx = string(13B)

	;\\ Notification window
	if keyword_set(home) then info_string = 'Homing Calibration Source' $
		else info_string = 'Driving to Calibration Source ' + string(source, f='(i01)') + $
			 ' at Pos: ' + string(motor_pos, f='(i0)')

		base = widget_base(col=1, group=misc.console_id, /floating)
		info = widget_label(base, value=info_string, font='Ariel*20*Bold', xs=400)
		widget_control, /realize, base

	;\\ Set the current limits
		comms_wrapper, port, dll_name, type='moxa', /write, data = 'LCC90'  + tx
		comms_wrapper, port, dll_name, type='moxa', /write, data = 'LPC120'  + tx

	if keyword_set(home) then begin
		;\\ Enable the motor
		comms_wrapper, port, dll_name, type='moxa', /write, data = 'EN'  + tx
		;\\ Call current position 0
		comms_wrapper, port, dll_name, type='moxa', /write, data = 'HO'  + tx
		;\\ Set a low speed, 5 RPM
		comms_wrapper, port, dll_name, type='moxa', /write, data = 'SP5'  + tx
		;\\ Drive two full revolutions, so we have to hit the stop at some point
		comms_wrapper, port, dll_name, type='moxa', /write, data = 'LA6000'  + tx

		;\\ Note the current time
		home_start_time = systime(/sec)
		;\\ Initiate the motion
		comms_wrapper, port, dll_name, type='moxa', /write, data = 'M'  + tx

		;\\ Wait 10 seconds
		while (systime(/sec) - home_start_time) lt 10 do begin
			wait, 0.5
			widget_control, set_value ='Homing Calibration Source ' + $
					string(10 - (systime(/sec) - home_start_time), f='(f0.1)'), info
		endwhile

		;\\ Call the home position 0
		comms_wrapper, port, dll_name, type='moxa', /write, data = 'HO'  + tx
		comms_wrapper, port, dll_name, type='moxa', /write, data = 'SP50'  + tx
		;\\ Drive a little bit away from it
		comms_wrapper, port, dll_name, type='moxa', /write, data = 'LA-10'  + tx
		comms_wrapper, port, dll_name, type='moxa', /write, data = 'M'  + tx
		wait, 2.

		print, 'Cal Source Homed'
		comms_wrapper, port, dll_name, type = 'moxa', /write, data = 'DI'+tx

	endif else begin

		comms_wrapper, port, dll_name, type = 'moxa', /write, data = 'EN'+tx
		comms_wrapper, port, dll_name, type='moxa', /write, data = 'LA' + string(motor_pos, f='(i0)') + tx
		comms_wrapper, port, dll_name, type='moxa', /write, data = 'M' + tx
		wait, 6.
		;comms_wrapper, port, dll_name, type = 'moxa', /write, data = 'DI'+tx

	endelse

	;\\ Close notification window
		if widget_info(base, /valid) eq 1 then widget_control, base, /destroy
end




;\\ FILTER SELECT ROUTINES
pro LaTrobe_filter, filter_number, $
					  log_path = log_path, $
				  	  misc, console

	if keyword_set(log_path) then cd, log_path, current = old_dir
	program_path = 'C:\MawsonCode\Filter wheel\'
	spawn, program_path + 'Filters.exe ' + string(filter_number, f='(i0)'), /noshell
	if keyword_set(log_path) then cd, old_dir

end




;\\ ETALON LEG ROUTINES
pro LaTrobe_etalon, dll, $
				   leg1_voltage, $
				   leg2_voltage, $
				   leg3_voltage, $
				   misc, console


	cmd = 'E1L1V' + string(leg1_voltage, format='(i4.4)') + string(13B)
	comms_wrapper, misc.port_map.etalon.number, misc.dll_name, type = 'moxa', /write, data = cmd
	wait, 0.08

	cmd = 'E1L2V' + string(leg2_voltage, format='(i4.4)') + string(13B)
	comms_wrapper, misc.port_map.etalon.number, misc.dll_name, type = 'moxa', /write, data = cmd
	wait, 0.08

	cmd = 'E1L3V' + string(leg3_voltage, format='(i4.4)') + string(13B)
	comms_wrapper, misc.port_map.etalon.number, misc.dll_name, type = 'moxa', /write, data = cmd
	wait, 0.08

end



;\\ IMAGE POST PROCESSING ROUTINES
pro LaTrobe_imageprocess, image

	image = 10*image
	empty_mean = ((mean(image[10:40, 10:40]) + mean(image[10:40, 471:501]) + $
				   mean(image[471:501, 10:40]) + mean(image[471:501, 471:501]))/4.)

	image = (200 + (image) - round(empty_mean)) > 0

end



;\\ INITIALISATION ROUTINES
pro LaTrobe_initialise, misc, console

	console->log, '** Mawson SDI **', 'InstrumentSpecific', /display

	;\\ Set up the com ports
	comms_wrapper, misc.port_map.cal_source.number, misc.dll_name, type = 'moxa', /open, errcode=errcode, moxa_setbaud=12
	console->log, 'Open Calibration Source Port: ' + string(errcode, f='(i0)'), 'InstrumentSpecific', /display
	comms_wrapper, misc.port_map.mirror.number, misc.dll_name, type = 'moxa', /open, errcode=errcode, moxa_setbaud=12
	console->log, 'Open Mirror Port: ' + string(errcode, f='(i0)'), 'InstrumentSpecific', /display
	comms_wrapper, misc.port_map.etalon.number, misc.dll_name, type = 'moxa', /open, errcode=errcode, moxa_setbaud=12
	console->log, 'Open Etalon Port: ' + string(errcode, f='(i0)'), 'InstrumentSpecific', /display


	;\\ Initialise Faulhaber motors
	tx = string(13B)
	comms_wrapper, misc.port_map.cal_source.number, misc.dll_name, type='moxa', /write, data = 'DI'+tx  ;\\ disable cal source motor
	comms_wrapper, misc.port_map.mirror.number, misc.dll_name, type='moxa', /write, data = 'EN'+tx 	  ;\\ enable mirror motor
	comms_wrapper, misc.port_map.mirror.number, misc.dll_name, type='moxa', /write, data = 'ANSW1'+string(13B)

end
