
function SDILockCalSource::init, data=data, restore_struc = restore_struc

	self.palette = data.palette
	self.need_timer = 0
	self.need_frame = 1
	self.obj_num = string(data.count, format = '(i0)')
	self.manager = data.manager
	self.console = data.console

	if data.recover eq 1 then begin

		;\\ Saved settings

		xsize 			= 400	;restore_struc.geometry.xsize
		ysize 			= 400	;restore_struc.geometry.ysize
		xoffset 		= restore_struc.geometry.xoffset
		yoffset 		= restore_struc.geometry.yoffset

	endif else begin

		;\\ Default settings

		xsize 	= 400
		ysize 	= 400
		xoffset = 100
		yoffset = 100

	endelse

	self.status = 'Idle'

	;\\ Get motor port
	ports = self.console -> get_port_map()
	self.port = ports.cal_source.number
	self.dll = self.console -> get_dll_name()

	;\\ Enable and set current motor pos to 0
	tx = string(13B)
	comms_wrapper, self.port, self.dll, type='moxa', /write, data = 'EN'  + tx
	comms_wrapper, self.port, self.dll, type='moxa', /write, data = 'SP10'  + tx
	comms_wrapper, self.port, self.dll, type='moxa', /write, data = 'LCC5'  + tx
	comms_wrapper, self.port, self.dll, type='moxa', /write, data = 'LPC10'  + tx


	;\\ Open the camera shutter
	self.console -> cam_shutteropen, 0

	font = 'Ariel*Bold*20'

	base = widget_base(xoffset = xoffset, yoffset = yoffset, mbar = menu, $
					   title = 'Lock Cal Source', group_leader = leader, col = 1)

		home_for = widget_button(base, value = 'Home Forward', uval = {tag:'start', dir:'forward'}, font=font)
		home_bac = widget_button(base, value = 'Home Backward', uval = {tag:'start', dir:'backward'}, font=font)
		stop_but  = widget_button(base, value = 'Stop', uval = {tag:'stop'}, font=font)
		for_but  = widget_button(base, value = 'Forward', uval = {tag:'forward'}, font=font)
		bak_but  = widget_button(base, value = 'Back', uval = {tag:'back'}, font=font)
		lok_but  = widget_button(base, value = 'Lock', uval = {tag:'lock'}, font=font)

	cmd_str_base = widget_base(base, col=1)
		lab = widget_label(cmd_str_base, value='Command String', font=font)
		cmd = widget_text(cmd_str_base, /editable, uval = {tag:'cmd_str'}, font=font, $
					uname='LockCalSource_'+self.obj_num+'cmd_input' )

	status_base = widget_base(base, col=1)
		stat_lab = widget_label(status_base, value = 'Status: ' + self.status, font = font, $
							    uname='LockCalSource_'+self.obj_num+'stat', xsize = 300)

	image_base = widget_base(base, col=1)
		draw = widget_draw(image_base, uname='LockCalSource_'+self.obj_num+'draw', xsize = 200, ysize=200)

	self.id = base
	widget_control, base, /realize
	return, 1

end



pro SDILockCalSource::cmd_str, event

	id = widget_info(self.id, find_by_uname = 'LockCalSource_'+self.obj_num+'cmd_input')
	widget_control, get_value = cmd_string, id
	print, 'Command String: ' + cmd_string
	comms_wrapper, self.port, self.dll, type='moxa', /write, data = cmd_string + string(13B)

end




pro SDILockCalSource::start, event

	widget_control, get_uval = uval, event.id
	dir = uval.dir

	if self.status eq 'Idle' then begin
		self.status = 'Homing'
		self.history[*] = 0.0
		self.pos = 0

		tx = string(13B)
		;\\ Call current position 0
		comms_wrapper, self.port, self.dll, type='moxa', /write, data = 'HO'  + tx
		;\\ Set a low speed, 5 RPM
		comms_wrapper, self.port, self.dll, type='moxa', /write, data = 'SP5'  + tx
		;\\ Set the current limits again to be safe
		comms_wrapper, self.port, self.dll, type='moxa', /write, data = 'LCC80'  + tx
		comms_wrapper, self.port, self.dll, type='moxa', /write, data = 'LPC110'  + tx
		;\\ Drive two full revolutions, so we have to hit the stop at some point
		if dir eq 'forward' then begin
			comms_wrapper, self.port, self.dll, type='moxa', /write, data = 'LA6000'  + tx
		endif
		if dir eq 'backward' then begin
			comms_wrapper, self.port, self.dll, type='moxa', /write, data = 'LA-6000'  + tx
		endif
		;\\ Note the current time
		self.home_start_time = systime(/sec)
		;\\ Initiate the motion
		comms_wrapper, self.port, self.dll, type='moxa', /write, data = 'M'  + tx
	endif

end

pro SDILockCalSource::auto_start, event

	self->start, 0

end

pro SDILockCalSource::stop, event

	self.status = 'Idle'
	tx = string(13B)
	;\\ Stop driving
	comms_wrapper, self.port, self.dll, type='moxa', /write, data = 'V0'  + tx

end


pro SDILockCalSource::frame_event, image, channel

	if self.status eq 'Homing' then begin

		;\\ Check elapsed time. We wait 20 seconds.
		if (systime(/sec) - self.home_start_time) gt 10. then begin

			self->stop, 0

		endif
	endif

	tvlct, r, g, b, /get
	loadct, 0, /silent
	draw_id = widget_info(self.id, find_by_uname='LockCalSource_'+self.obj_num+'draw')
	widget_control, get_value = wind_id, draw_id
	wset, wind_id
	tvscl, congrid(image, 200, 200)
	tvlct, r, g, b

	stat_id = widget_info(self.id, find_by_uname='LockCalSource_'+self.obj_num+'stat')
	widget_control, set_value = 'Status: ' + self.status + ', Signal: ' + $
					string(total(image) / 10.^8, f='(f0.5)') + ' x1E8', stat_id



			;self.history(self.pos-1) = total(image)
			;wset, draw
			;if self.pos gt 1 then plot, self.history[0:self.pos-1]/max(self.history), thick=2, $
			;							xtitle='Position', ytitle='Signal / 10^8', $
			;							title = self.status, /xstyle


;	if self.status eq 'Positioning' then begin
;
;		;\\ Turn until a dark spot is reached
;
;			if self.pos gt 0 then begin
;				self.history(self.pos-1) = total(image)
;				if total(image) lt self.curr_min then self.curr_min = total(image)
;				wset, draw
;				if self.pos gt 1 then plot, self.history(0:self.pos-1)/10.^8, thick=2, $
;											xtitle='Position', ytitle='Signal / 10^8', $
;											title = self.status, /xstyle
;			endif else begin
;				self.curr_min = total(image)
;			endelse
;
;			if self.pos gt 20 then begin
;				coeffs = linfit(findgen(21),self.history(self.pos-21:self.pos-1)/10.^8)
;				if coeffs(1) lt 0.0001 then begin
;					self.history(*) = 0.0
;					self.pos = 0
;					self.status = 'Homing'
;					goto, LOCK_CAL_SOURCE_HOMING
;				endif
;			endif
;
;			self.pos = self.pos + 1
;
;			data_str = 'V1'
;			t1 = systime(/sec)
;			res = drive_motor(self.port, self.dll, verbatim = data_str)
;			wait, 1.0
;			data_str = 'V0'
;			res = drive_motor(self.port, self.dll, verbatim = data_str)
;			t2 = systime(/sec)
;
;	endif
;
;	LOCK_CAL_SOURCE_HOMING:
;
;	if self.status eq 'Homing' then begin
;
;			pos_id = widget_info(self.id, find_by_uname='LockCalSource_'+self.obj_num+'pos')
;			widget_control, set_value = string(self.pos,f='(i0)'), pos_id
;
;		;\\ Get the image total
;			if self.pos gt 0 then begin
;				self.history(self.pos-1) = total(image)
;				print, total(image) / 10.^8
;				;if total(image) / 10.^8 gt .9 and total(image) / 10.^8 lt 2.0  then begin
;				if total(image) / 10.^8 gt 7 then begin
;					self.status = 'Idle'
;					res = drive_motor(self.port, self.dll, control = 'setpos0')
;					;smap = {s0:750, s1:1500, s2:2250, s3:0}
;					smap = {s0:2250, s1:0, s2:750, s3:1500}
;					self.console -> mot_sel_cal, 0, set_source = 3
;					self.console -> set_source_map, smap
;					self.console -> save_current_settings
;					goto, END_HOMING
;				endif
;			endif
;
;			wset, draw
;			!p.multi = 0
;			!p.position = 0
;			if self.pos gt 1 then plot, self.history(0:self.pos-1)/10.^8, thick=2, $
;										xtitle='Position', ytitle='Signal / 10^8', $
;										title = self.status, /xstyle
;
;		;\\ Turn
;			motor_pos = self.pos * 10
;
;
;			data_str = 'V1'
;			t1 = systime(/sec)
;			res = drive_motor(self.port, self.dll, verbatim = data_str)
;			wait, 1.0
;			data_str = 'V0'
;			res = drive_motor(self.port, self.dll, verbatim = data_str)
;			t2 = systime(/sec)
;
;			if self.pos lt 300 then self.pos = self.pos + 1 else self.status = 'Idle'
;
;		;\\ Find laser peaks
;;			if self.pos lt 240 then begin
;;				self.pos = self.pos + 1
;;			endif else begin
;;
;;				self.pos = 0
;;
;;				m = moment(self.history, sdev = stdev)
;;
;;				npeaks = 0
;;				ndevs  = 10.
;;
;;				while npeaks lt 2 do begin
;;
;;					filter = where(self.history gt m(0) + ndevs*stdev, n)
;;
;;					if n gt 1 then begin
;;						find_gaps, filter, indxs, npeaks
;;					endif
;;
;;					ndevs = ndevs - 0.5
;;					if ndevs lt 0 then break
;;
;;				endwhile
;;
;;			if npeaks ne 2 then begin
;;				self.status = 'Idle'
;;				print, 'Unable to find 2 peaks'
;;			endif else begin
;;				;\\ Find index dif between peaks, convert to pulses/index
;;					pk1 = float(indxs(0,0)) + (float(indxs(0,1)) - float(indxs(0,0)))/2.
;;					pk2 = float(indxs(1,0)) + (float(indxs(1,1)) - float(indxs(1,0)))/2.
;;					if pk2 gt pk1 then pos_diff = pk2-pk1 else pos_diff = pk1-pk2
;;					pulses_per_index = 1500. / pos_diff
;;				;\\ Get values at peaks to fix which laser is which (green > red)
;;					hist_copy = smooth(self.history/(10.^8), 10, /edge)
;;					pk1_val = hist_copy(pk1)
;;					pk2_val = hist_copy(pk2)
;;				;\\ Use red laser as reference, so drive to red laser peak
;;					if pk1_val gt pk2_val then begin
;;						;\\ Pk1 is green, so drive to Pk2
;;							drive_to_pos = pulses_per_index * pk2
;;							data_str = 'LA' + string(fix(drive_to_pos),f='(i0)')
;;							res = drive_motor(self.port, self.dll, verbatim = data_str)
;;							data_str = 'M'
;;							res = drive_motor(self.port, self.dll, verbatim = data_str)
;;							wait, 5.
;;							data_str = 'V0'
;;							res = drive_motor(self.port, self.dll, verbatim = data_str)
;;					endif else begin
;;						;\\ Pk2 is green, so drive to Pk1
;;							drive_to_pos = pulses_per_index * pk1
;;							data_str = 'LA' + string(fix(drive_to_pos),f='(i0)')
;;							res = drive_motor(self.port, self.dll, verbatim = data_str)
;;							data_str = 'M'
;;							res = drive_motor(self.port, self.dll, verbatim = data_str)
;;							wait, 5.
;;							data_str = 'V0'
;;							res = drive_motor(self.port, self.dll, verbatim = data_str)
;;					endelse
;;			endelse
;;
;;			self.status = 'Idle'
;;			print, drive_to_pos
;;			print, pulses_per_index
;;			print, pos_diff
;;			print, pk1, pk2
;;			print, pk1_val, pk2_val
;;
;;		endelse
;
;	endif
;
;END_HOMING:

end

pro SDILockCalSource::forward, event

	if self.status eq 'Idle' then begin
		self.status = 'Forward'
		data_str = 'V1'
			t1 = systime(/sec)
			res = drive_motor(self.port, self.dll, verbatim = data_str)
			wait, 2
			data_str = 'V0'
			res = drive_motor(self.port, self.dll, verbatim = data_str)
			t2 = systime(/sec)
		self.status = 'Idle'
	endif

end

pro SDILockCalSource::back, event

	if self.status eq 'Idle' then begin
		self.status = 'Backward'
		data_str = 'V-1'
			t1 = systime(/sec)
			res = drive_motor(self.port, self.dll, verbatim = data_str)
			wait, 2
			data_str = 'V0'
			res = drive_motor(self.port, self.dll, verbatim = data_str)
			t2 = systime(/sec)
		self.status = 'Idle'
	endif

end

pro SDILockCalSource::lock, event

	if self.status eq 'Idle' then begin
		res = drive_motor(self.port, self.dll, control = 'setpos0')
		smap = {s0:2250, s1:0, s2:750, s3:1500}
		self.console -> mot_sel_cal, 0, set_source = 1
		self.console -> set_source_map, smap
		self.console -> save_current_settings
	endif

end


;\\ Retrieves the objects structure data for restoring, so only needs save info (required)

function SDILockCalSource::get_settings

	struc = {id:self.id, geometry:self.geometry, need_timer:self.need_timer, $
			 need_frame:self.need_frame}

	return, struc

end


;\\ Cleanup routine

pro SDILockCalSource::cleanup, log


end



pro SDILockCalSource__define

	void = {SDILockCalSource, id:0L, $
							  port:0L, $
							  dll:'', $
							  status:'', $
							  pos:0, $
							  history:fltarr(300), $
							  home_start_time:0.0, $
							  curr_min:0.0, inherits XDIBase}

end