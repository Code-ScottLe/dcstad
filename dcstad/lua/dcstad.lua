--
-- Created by IntelliJ IDEA.
-- User: ergin.ozkucur
-- Date: 20/02/15
-- Time: 21:16
-- To change this template use File | Settings | File Templates.
--

dcstad = {
    default_output_file = nil,
    aircraftstate=nil,
    socket=nil,
    mp=nil,
    tcpserver=nil,
    udpserver=nil,
    tcpclient=nil,
    timout=nil,
    isconnected=nil,
    clientip=nil,
    clientport=nil,
    prevLat=nil,
    prevLong=nil,
    lfs=nil,

    tadstart=function(self)
        self.aircraftstate={["posx"]=41.844450,["posy"]=41.955505,["bearing"]=0.2,["selectedwp"]=0,["waypoints"]={},["airobjects"]={}}
        self.timout=0.001
        self.isconnected=0

        self.lfs=require('lfs')
        --self.default_output_file = io.open(self.lfs.writedir().."/Logs/Export.log", "w")

        package.path  = package.path..";"..self.lfs.currentdir().."/LuaSocket/?.lua"
        package.cpath = package.cpath..";"..self.lfs.currentdir().."/LuaSocket/?.dll"
        package.path  = package.path..";"..self.lfs.writedir().."/Scripts/MessagePack/?.lua"
        self.socket = require("socket")
        self.mp = require("MessagePack")
        --self.default_output_file:write(string.format("Start\n"))
        self.tcpserver=self.socket.bind("*", 5556)
        self.tcpserver:settimeout(self.timout)
        self.udpserver = self.socket.udp()
    end,
    tadstop=function(self)
        if self.default_output_file then
            self.default_output_file:close()
            self.default_output_file = nil
        end
        if self.tcpclient then
            self.socket.try(self.tcpclient:close())
        end
        self.socket.try(self.tcpserver:close())
        self.socket.try(self.udpserver:close())
    end,


    tablecount=function(self,tbl)
        local c=0
        for k in pairs(tbl) do c=c+1 end
        return c
    end,

    table_print=function(self,tt, indent, done)
        done = done or {}
        indent = indent or 0
        if type(tt) == "table" then
            local sb = {}
            for key, value in pairs (tt) do
                table.insert(sb, string.rep (" ", indent)) -- indent it
                if type (value) == "table" and not done [value] then
                    done [value] = true
                    if "number" == type(key) then
                        table.insert(sb, string.format("%d = {\n",tostring(key)));
                    else
                        table.insert(sb, string.format("%s = {\n",tostring(key)));
                    end
                    --table.insert(sb, "{\n");
                    table.insert(sb, self:table_print (value, indent + 2, done))
                    table.insert(sb, string.rep (" ", indent)) -- indent it
                    table.insert(sb, "}\n");
                elseif "number" == type(key) then
                    table.insert(sb, string.format("%d = \"%s\"\n",tostring (key), tostring(value)))
                else
                    table.insert(sb, string.format(
                        "%s = \"%s\"\n", tostring (key), tostring(value)))
                end
            end
            return table.concat(sb)
        else
            return tt .. "\n"
        end
    end,

    table_to_string=function( self,tbl )
        if  "nil"       == type( tbl ) then
            return tostring(nil)
        elseif  "table" == type( tbl ) then
            return self:table_print(tbl)
        elseif  "string" == type( tbl ) then
            return tbl
        else
            return tostring(tbl)
        end
    end,

    readAndSendData=function(self)
        if self.isconnected==1 then
            local line,error=self.tcpclient:receive()
            if error=="closed" then
                --self.default_output_file:write("closed\n")
                self.socket.try(self.tcpclient:close())
                self.isconnected=0
            else
                local selfdata=LoGetSelfData()

                if selfdata then
                    self.aircraftstate["posy"]=selfdata.LatLongAlt.Lat;
                    self.aircraftstate["posx"]=selfdata.LatLongAlt.Long;
                    self.aircraftstate["bearing"]=selfdata.Heading;

                    --self.default_output_file:write("objects:\n")
                    --self.default_output_file:write(string.format("%s",self:table_to_string(LoGetWorldObjects())))
                    --self.default_output_file:write("wings:\n")
                    --self.default_output_file:write(string.format("%s",self:table_to_string(LoGetWingInfo())))
                    self.aircraftstate["airobjects"]={}
                    local allobjects=LoGetWorldObjects()
                    for k,v in pairs(allobjects) do
                        if (v.Type.level1==1 and (v.Type.level2==1 or v.Type.level2==2) and v.CoalitionID==selfdata.CoalitionID and k~=LoGetPlayerPlaneId()) then
                            local ao={}
                            ao["posy"]=v.LatLongAlt.Lat
                            ao["posx"]=v.LatLongAlt.Long
                            ao["bearing"]=v.Heading
                            ao["groupid"]=1
                            self.aircraftstate["airobjects"][k]=ao
                        end
                    end
                    local wings=LoGetWingInfo()
                    for k,v in pairs(wings) do
                        local ao=self.aircraftstate["airobjects"][tonumber(v.wingmen_id)]
                        if ao then
                            ao.groupid=0
                        end
                    end
                    --self.default_output_file:write("refined:\n")
                    --self.default_output_file:write(string.format("%s",self:table_to_string(self.aircraftstate)))
                end
                local route = LoGetRoute()
                if route then
                    local latlong = LoLoCoordinatesToGeoCoordinates(route.goto_point.world_point.x,route.goto_point.world_point.z)
                    local wp={}
                    wp["posy"]=latlong.latitude
                    wp["posx"]=latlong.longitude
                    wp["id"]=route.goto_point.this_point_num-1
                    self.aircraftstate["waypoints"][wp["id"]]=wp
                    self.aircraftstate["selectedwp"]=wp["id"]
                end
                --self.default_output_file:write(string.format("sending %f %f %f\n",self.aircraftstate['posx'],self.aircraftstate['posy'],self.aircraftstate['bearing']))
                local buffer={}
                self.mp.packers['float'](buffer,self.aircraftstate['posx'])
                self.mp.packers['float'](buffer,self.aircraftstate['posy'])
                self.mp.packers['float'](buffer,self.aircraftstate['bearing'])
                self.mp.packers['signed'](buffer,self:tablecount(self.aircraftstate['waypoints']))
                --self.default_output_file:write(string.format("wpsize %d\n",self:tablecount(self.aircraftstate['waypoints'])))
                for _,v in pairs(self.aircraftstate['waypoints']) do
                    --self.default_output_file:write(string.format("wp: %f %f \n",v['posx'],v['posy']))
                    self.mp.packers['float'](buffer,v['posx'])
                    self.mp.packers['float'](buffer,v['posy'])
                    self.mp.packers['signed'](buffer,v['id'])
                end
                self.mp.packers['signed'](buffer,self.aircraftstate['selectedwp'])

                self.mp.packers['signed'](buffer,self:tablecount(self.aircraftstate['airobjects']))
                for _,v in pairs(self.aircraftstate['airobjects']) do
                    --self.default_output_file:write(string.format("wp: %f %f \n",v['posx'],v['posy']))
                    self.mp.packers['float'](buffer,v['posx'])
                    self.mp.packers['float'](buffer,v['posy'])
                    self.mp.packers['float'](buffer,v['bearing'])
                    self.mp.packers['signed'](buffer,v['groupid'])
                end
                self.udpserver:sendto(table.concat(buffer), self.clientip, 5555)
            end
        else
            local readable, _, err = self.socket.select({self.tcpserver}, nil,self.timout)
            if readable[1] then
                if self.isconnected==0 then
                    self.tcpclient=self.tcpserver:accept()
                    if self.tcpclient then
                        self.tcpclient:settimeout(self.timout)
                        self.clientip,self.clientport=self.tcpclient:getpeername()
                        self.isconnected=1
                    end
                else

                end
            end
        end
    end,


    tadupdate=function(self)
        local status,err = pcall(self.readAndSendData,self)

        if not status then
            --self.default_output_file:write(err)
        end
    end
}


do
    local starttmp=LuaExportStart;
    LuaExportStart=function()
        dcstad:tadstart()
        if starttmp then
            starttmp()
        end
    end

    local updatetmp=LuaExportActivityNextEvent;
    LuaExportActivityNextEvent=function(t)
        dcstad:tadupdate()
        if updatetmp then
            return updatetmp(t);
        else
            return t+0.25
        end
    end

    local stoptmp=LuaExportStop;
    LuaExportStop=function()
        dcstad:tadstop()
        if stoptmp then
            stoptmp();
        end
    end
end



-- dcs api documentation

-- Data export script for DCS, version 1.2.
-- Copyright (C) 2006-2014, Eagle Dynamics.
-- See http://www.lua.org for Lua script system info
-- We recommend to use the LuaSocket addon (http://www.tecgraf.puc-rio.br/luasocket)
-- to use standard network protocols in Lua scripts.
-- LuaSocket 2.0 files (*.dll and *.lua) are supplied in the Scripts/LuaSocket folder
-- and in the installation folder of the DCS.

-- Expand the functionality of following functions for your external application needs.
-- Look into Saved Games\DCS\Logs\dcs.log for this script errors, please.

--[[
-- Uncomment if using Vector class from the Scripts\Vector.lua file
local lfs = require('lfs')
LUA_PATH = "?;?.lua;"..lfs.currentdir().."/Scripts/?.lua"
require 'Vector'
-- See the Scripts\Vector.lua file for Vector class details, please.
--]]


--[[

-- Lock On supports Lua coroutines using internal LoCreateCoroutineActivity() and
-- external CoroutineResume() functions. Here is an example of using scripted coroutine.

Coroutines = {}	-- global coroutines table
CoroutineIndex = 0	-- global last created coroutine index

-- This function will be called by Lock On model timer for every coroutine to resume it
function CoroutineResume(index, tCurrent)
	-- Resume coroutine and give it current model time value
	coroutine.resume(Coroutines[index], tCurrent)
	return coroutine.status(Coroutines[index]) ~= "dead"
	-- If status == "dead" then Lock On activity for this coroutine dies too
end

-- Coroutine function example using coroutine.yield() to suspend
function f(t)
	local tNext = t
	local file = io.open("./Temp/Coroutine.log", "w")
	file:write(string.format("t = %f, started\n", tNext))
	tNext = coroutine.yield()
	for i = 1,10 do
		file:write(string.format("t = %f, continued\n", tNext))
		tNext = coroutine.yield()
	end
	file:write(string.format("t = %f, finished\n", tNext))
	file:close()
end

-- Create your coroutines and save them in Coriutines table, e.g.:
CoroutineIndex = CoroutineIndex + 1
Coroutines[CoroutineIndex] = coroutine.create(f)

-- Use LoCreateCoroutineActivity(index, tStart, tPeriod) to plan your coroutines
-- activity at model times, e.g.:
LoCreateCoroutineActivity(CoroutineIndex, 1.0, 3.0) -- to start at 1.0 second with 3.0 seconds period
-- Coroutine output in the Coroutine.log file:
-- t = 1.000000, started
-- t = 4.000000, continued
-- t = 7.000000, continued
-- t = 10.000000, continued
-- t = 13.000000, continued
-- t = 16.000000, continued
-- t = 19.000000, continued
-- t = 22.000000, continued
-- t = 25.000000, continued
-- t = 28.000000, continued
-- t = 31.000000, continued
-- t = 34.000000, finished
--]]

--[[ You can use registered Lock On internal data exporting functions in this script
and in your scripts called from this script.

Note: following functions are implemented for exporting technology experiments only,
so they may be changed or removed in the future by developers.

All returned values are Lua numbers if not pointed other type.

Output:
LoGetModelTime() -- returns current model time (args - 0, results - 1 (sec))
LoGetMissionStartTime() -- returns mission start time (args - 0, results - 1 (sec))
LoGetPilotName() -- (args - 0, results - 1 (text string))
LoGetPlayerPlaneId() -- (args - 0, results - 1 (number))
LoGetIndicatedAirSpeed() -- (args - 0, results - 1 (m/s))
LoGetTrueAirSpeed() -- (args - 0, results - 1 (m/s))
LoGetAltitudeAboveSeaLevel() -- (args - 0, results - 1 (meters))
LoGetAltitudeAboveGroundLevel() -- (args - 0, results - 1 (meterst))
LoGetAngleOfAttack() -- (args - 0, results - 1 (rad))
LoGetAccelerationUnits() -- (args - 0, results - table {x = Nx,y = NY,z = NZ} 1 (G))
LoGetVerticalVelocity()  -- (args - 0, results - 1(m/s))
LoGetMachNumber()        -- (args - 0, results - 1)
LoGetADIPitchBankYaw()   -- (args - 0, results - 3 (rad))
LoGetMagneticYaw()       -- (args - 0, results - 1 (rad)
LoGetGlideDeviation()    -- (args - 0,results - 1)( -1 < result < 1)
LoGetSideDeviation()     -- (args - 0,results - 1)( -1 < result < 1)
LoGetSlipBallPosition()  -- (args - 0,results - 1)( -1 < result < 1)
LoGetBasicAtmospherePressure() -- (args - 0,results - 1) (mm hg)
LoGetControlPanel_HSI()  -- (args - 0,results - table)
result =
{
	ADF_raw, (rad)
	RMI_raw, (rad)
	Heading_raw, (rad)
	HeadingPointer, (rad)
	Course, (rad)
	BearingPointer, (rad)
	CourseDeviation, (rad)
}
LoGetEngineInfo() -- (args - 0 ,results = table)
engineinfo =
{
	RPM = {left, right},(%)
	Temperature = { left, right}, (Celcium degrees)
	HydraulicPressure = {left ,right},kg per square centimeter
	FuelConsumption   = {left ,right},kg per sec
    fuel_internal      -- fuel quantity internal tanks	kg
	fuel_external      -- fuel quantity external tanks	kg

}

LoGetRoute()  -- (args - 0,results = table)
get_route_result =
{
	goto_point, -- next waypoint
	route       -- all waypoints of route (or approach route if arrival or landing)
}
waypoint_table =
{
	this_point_num,        -- number of point ( >= 0)
	world_point = {x,y,z}, -- world position in meters
	speed_req,             -- speed at point m/s
	estimated_time,        -- sec
	next_point_num,		   -- if -1 that's the end of route
	point_action           -- name of action "ATTACKPOINT","TURNPOINT","LANDING","TAKEOFF"
}
LoGetNavigationInfo() (args - 0,results - 1( table )) -- information about ACS
get_navigation_info_result =
{
	SystemMode = {master,submode}, -- (string,string) current mode and submode
--[=[
	master values (depend of plane type)
				"NAV"  -- navigation
			    "BVR"  -- beyond visual range AA mode
				"CAC"  -- close air combat
				"LNG"  -- longitudinal mode
				"A2G"  -- air to ground
				"OFF"  -- mode is absent
	submode values (depend of plane type and master mode)
	"NAV" submodes
	{
		"ROUTE"
		"ARRIVAL"
		"LANDING"
		"OFF"
	}
	"BVR" submodes
	{
		"GUN"   -- Gunmode
		"RWS"   -- RangeWhileSearch
		"TWS"   -- TrackWhileSearch
		"STT"   -- SingleTrackTarget (Attack submode)
		"OFF"
	}
	"CAC" submodes
	{
		"GUN"
		"VERTICAL_SCAN"
		"BORE"
		"HELMET"
		"STT"
		"OFF"
	}
	"LNG" submodes
	{
		"GUN"
		"OFF"
		"FLOOD"  -- F-15 only
	}
	"A2G" submodes
	{
		"GUN"
		"ETS"       -- Emitter Targeting System On
		"PINPOINT"
		"UNGUIDED"  -- unguided weapon (free fall bombs, dispensers , rockets)
		"OFF"
	}
--]=]
	Requirements =  -- required parameters of flight
	{
		roll,	   -- required roll,pitch.. , etc.
		pitch,
		speed,
		vertical_speed,
		altitude,
	}
	ACS =   -- current state of the Automatic Control System
	{
		mode = string ,
		--[=[
			mode values  are :
					"FOLLOW_ROUTE",
					"BARO_HOLD",
					"RADIO_HOLD",
					"BARO_ROLL_HOLD",
					"HORIZON_HOLD",
					"PITCH_BANK_HOLD",
					"OFF"
		--]=]
		autothrust , -- 1(true) if autothrust mode is on or 0(false) when not;
	}
}
LoGetMCPState() -- (args - 0, results - 1 (table of key(string).value(boolean))
	returned table keys for LoGetMCPState():
		"LeftEngineFailure"
		"RightEngineFailure"
		"HydraulicsFailure"
		"ACSFailure"
		"AutopilotFailure"
		"AutopilotOn"
		"MasterWarning"
		"LeftTailPlaneFailure"
		"RightTailPlaneFailure"
		"LeftAileronFailure"
		"RightAileronFailure"
		"CanopyOpen"
		"CannonFailure"
		"StallSignalization"
		"LeftMainPumpFailure"
		"RightMainPumpFailure"
		"LeftWingPumpFailure"
		"RightWingPumpFailure"
		"RadarFailure"
		"EOSFailure"
		"MLWSFailure"
		"RWSFailure"
		"ECMFailure"
		"GearFailure"
		"MFDFailure"
		"HUDFailure"
		"HelmetFailure"
		"FuelTankDamage"
LoGetObjectById() -- (args - 1 (number), results - 1 (table))
 Returned object table structure:
 {
	Name =
	Type =  {level1,level2,level3,level4},  ( see Scripts/database/wsTypes.lua) Subtype is absent  now
	Country   =   number ( see Scripts/database/db_countries.lua
	Coalition =
	CoalitionID = number ( 1 or 2 )
	LatLongAlt = { Lat = , Long = , Alt = }
	Heading =   radians
	Pitch      =   radians
	Bank      =  radians
	Position = {x,y,z} -- in internal DCS coordinate system ( see convertion routnes below)
	-- only for units ( Planes,Hellicopters,Tanks etc)
	UnitName    = unit name from mission (UTF8)
	GroupName = unit name from mission (UTF8)
 }


LoGetWorldObjects() -- (args - 0- 1, results - 1 (table of object tables))  arg can be "units" (default) or "ballistic" , ballistic - for different type of unguided munition ()bombs,shells,rockets)
 Returned table index = object identificator
 Returned object table structure (see LoGetObjectById())

LoGetSelfData return the same result as LoGetObjectById but only for your aircraft and not depended on anti-cheat setting in Export/Config.lua

LoGetAltitude(x, z) -- (args - 2 : meters, results - 1 : altitude above terrain surface, meters)

LoGetCameraPosition() -- (args - 0, results - 1 : view camera current position table:
	{
		x = {x = ..., y = ..., z = ...},	-- orientation x-vector
		y = (x = ..., y = ..., z = ...},	-- orientation y-vector
		z = {x = ..., y = ..., z = ...},	-- orientation z-vector
		p = {x = ..., y = ..., z = ...}		-- point vector
    }
    all coordinates are in meters. You can use Vector class for position vectors.

-- Weapon Control System
LoGetNameByType () -- args 4 (number : level1,level2,level3,level4), result string

LoGetTargetInformation()       -- (args - 0, results - 1 (table of current targets tables))
LoGetLockedTargetInformation() -- (args - 0, results - 1 (table of current locked targets tables))
 this functions return the table of the next target data
 target =
 {
	ID ,                                  -- world ID (may be 0 ,when ground point track)
	type = {level1,level2,level3,level4}, -- world database classification
	country = ,                           -- object country
	position = {x = {x,y,z},   -- orientation X ort
	            y = {x,y,z},   -- orientation Y ort
				z = {x,y,z},   -- orientation Z ort
				p = {x,y,z}}   -- position of the center
	velocity =        {x,y,z}, -- world velocity vector m/s
	distance = ,               -- distance in meters
	convergence_velocity = ,   -- closing speed in m/s
	mach = ,                   -- M number
	delta_psi = ,              -- aspect angle rad
	fim = ,                    -- viewing angle horizontal (in your body axis) rad
	fin = ,                    -- viewing angle vertical   (in your body axis) rad
	flags = ,				   -- field with constants detemining  method of the tracking
								--	whTargetRadarView		= 0x0002;	-- Radar review (BVR)
								--	whTargetEOSView			= 0x0004;	-- EOS   review (BVR)
								--	whTargetRadarLock		= 0x0008;	-- Radar lock (STT)  == whStaticObjectLock (pinpoint) (static objects,buildings lock)
								--	whTargetEOSLock			= 0x0010;	-- EOS   lock (STT)  == whWorldObjectLock (pinpoint)  (ground units lock)
								--	whTargetRadarTrack		= 0x0020;	-- Radar lock (TWS)
								--	whTargetEOSTrack		= 0x0040;	-- Radar lock (TWS)  == whImpactPointTrack (pinpoint) (ground point track)
								--	whTargetNetHumanPlane	= 0x0200;	-- net HumanPlane
								--	whTargetAutoLockOn  	= 0x0400;	-- EasyRadar  autolockon
								--	whTargetLockOnJammer  	= 0x0800;	-- HOJ   mode

	reflection = ,             -- target cross section square meters
	course = ,                 -- target course rad
	isjamming = ,              -- target ECM on or not
	start_of_lock = ,          -- time of the beginning of lock
	forces = { x,y,z},         -- vector of the acceleration units
	updates_number = ,         -- number of the radar updates

	jammer_burned = true/false -- indicates that jammer are burned
 }
LoGetSightingSystemInfo() -- sight system info
{
	Manufacturer  = "RUS"/"USA"
	LaunchAuthorized  = true/false
	ScanZone =
		{
				position
				{
					azimuth
					elevation
					if Manufacturer  == "RUS" then
					        distance_manual
					       exceeding_manual
					end
				   }
				coverage_H
				{
					min
					max
				}
				size
				{
					azimuth
					elevation
				}
		}
		scale
		{
			distance
			azimuth
		}
		TDC
		{
				x
				y
		}

		radar_on   = true/false
		optical_system_on= true/false
		ECM_on= true/false
		laser_on= true/false

		PRF =
		{
			current ,    -- current PRF value ( changed in ILV mode ) , values are "MED" or "HI"
			selection ,  -- selection value can be  "MED"  "HI" or "ILV"
		}

}
LoGetTWSInfo() -- return Threat Warning System status (result  the table )
result_of_LoGetTWSInfo =
{
	Mode = , -- current mode (0 - all ,1 - lock only,2 - launch only
	Emitters = {table of emitters}
}
emitter_table =
{
	ID =, -- world ID
	Type = {level1,level2,level3,level4}, -- world database classification of emitter
	Power =, -- power of signal
	Azimuth =,
	Priority =,-- priority of emitter (int)
	SignalType =, -- string with vlues: "scan" ,"lock", "missile_radio_guided","track_while_scan";
}
LoGetPayloadInfo() -- return weapon stations
result_of_LoGetPayloadInfo
{
	CurrentStation = , -- number of current station (0 if no station selected)
	Stations = {},-- table of stations
	Cannon =
	{
		shells -- current shells count
	}
}
station
{
	container = true/false , -- is station container
	weapon    = {level1,level2,level3,level4} , -- world database classification of weapon
	count = ,
}
LoGetMechInfo() -- mechanization info
result_is =
{
	gear          = {status,value,main = {left = {rod},right = {rod},nose =  {rod}}}
	flaps		  = {status,value}
	speedbrakes   = {status,value}
	refuelingboom = {status,value}
	airintake     = {status,value}
	noseflap      = {status,value}
	parachute     = {status,value}
	wheelbrakes   = {status,value}
	hook          = {status,value}
	wing          = {status,value}
	canopy        = {status,value}
	controlsurfaces = {elevator = {left,right},eleron = {left,right},rudder = {left,right}} -- relative vlues (-1,1) (min /max) (sorry:(
}

LoGetRadioBeaconsStatus() -- beacons lock
{
	airfield_near	,
	airfield_far,
	course_deviation_beacon_lock	,
	glideslope_deviation_beacon_lock
}

LoGetWingInfo() -- your wingmens info result is vector of wingmens with value:
wingmen_is =
{
	wingmen_id   -- world id of wingmen
	wingmen_position -- world position {x = {x,y,z},   -- orientation X ort
										y = {x,y,z},   -- orientation Y ort
										z = {x,y,z},   -- orientation Z ort
										p = {x,y,z}}   -- position of the center
	current_target -- world id of target
	ordered_target -- world id of target
	current_task   -- name of task
	ordered_task   -- name of task
	--[=[
	name can be :
			"NOTHING"
			"ROUTE"
			"DEPARTURE"
			"ARRIVAL"
			"REFUELING"
			"SOS"    -- Save Soul of your Wingmen :)
			"ROUTE"
			"INTERCEPT"
			"PATROL"
			"AIR_ATTACK"
			"REFUELING"
			"AWACS"
			"RECON"
			"ESCORT"
			"PINPOINT"
			"CAS"
			"MISSILE_EVASION"
			"ENEMY_EVASION"
			"SEAD"
			"ANTISHIP"
			"RUNWAY_ATTACK"
			"TRANSPORT"
			"LANDING"
			"TAKEOFF"
			"TAXIING"
	--]=]

}

Coordinates convertion :
{x,y,z}				  = LoGeoCoordinatesToLoCoordinates(longitude_degrees,latitude_degrees)
{latitude,longitude}  = LoLoCoordinatesToGeoCoordinates(x,z);

LoGetVectorVelocity		  =  {x,y,z} -- vector of self velocity (world axis)
LoGetAngularVelocity	  =  {x,y,z} -- angular velocity euler angles , rad per sec
LoGetVectorWindVelocity   =  {x,y,z} -- vector of wind velocity (world axis)
LoGetWingTargets		  =   table of {x,y,z}
LoGetSnares               =   {chaff,flare}
Input:
LoSetCameraPosition(pos) -- (args - 1: view camera current position table, results - 0)
	pos table structure:
	{
		x = {x = ..., y = ..., z = ...},	-- orientation x-vector
		y = (x = ..., y = ..., z = ...},	-- orientation y-vector
		z = {x = ..., y = ..., z = ...},	-- orientation z-vector
		p = {x = ..., y = ..., z = ...}		-- point vector
    }
    all coordinates are in meters. You can use Vector class for position vectors.

LoSetCommand(command, value) -- (args - 2, results - 0)
-1.0 <= value <= 1.0

Some analogous joystick/mouse input commands:
command = 2001 - joystick pitch
command = 2002 - joystick roll
command = 2003 - joystick rudder
-- Thrust values are inverted for some internal reasons, sorry.
command = 2004 - joystick thrust (both engines)
command = 2005 - joystick left engine thrust
command = 2006 - joystick right engine thrust
command = 2007 - mouse camera rotate left/right
command = 2008 - mouse camera rotate up/down
command = 2009 - mouse camera zoom
command = 2010 - joystick camera rotate left/right
command = 2011 - joystick camera rotate up/down
command = 2012 - joystick camera zoom
command = 2013 - mouse pitch
command = 2014 - mouse roll
command = 2015 - mouse rudder
-- Thrust values are inverted for some internal reasons, sorry.
command = 2016 - mouse thrust (both engines)
command = 2017 - mouse left engine thrust
command = 2018 - mouse right engine thrust
command = 2019 - mouse trim pitch
command = 2020 - mouse trim roll
command = 2021 - mouse trim rudder
command = 2022 - joystick trim pitch
command = 2023 - joystick trim roll
command = 2024 - trim rudder
command = 2025 - mouse rotate radar antenna left/right
command = 2026 - mouse rotate radar antenna up/down
command = 2027 - joystick rotate radar antenna left/right
command = 2028 - joystick rotate radar antenna up/down
command = 2029 - mouse MFD zoom
command = 2030 - joystick MFD zoom
command = 2031 - mouse move selecter left/right
command = 2032 - mouse move selecter up/down
command = 2033 - joystick move selecter left/right
command = 2034 - joystick move selecter up/down

Some discrete keyboard input commands (value is absent):
command = 7	-- Cockpit view
command = 8	-- External view
command = 9	-- Fly-by view
command = 10 -- Ground units view
command = 11 -- Civilian transport view
command = 12 -- Chase view
command = 13 -- Navy view
command = 14 -- Close air combat view
command = 15 -- Theater view
command = 16 -- Airfield (free camera) view
command = 17 --	Instruments panel view on
command = 18 -- Instruments panel view off
command = 19 -- Padlock toggle
command = 20 --	Stop padlock (in cockpit only)
command = 21 --	External view for my plane
command = 22 --	Automatic chase mode for launched weapon
command = 23 --	View allies only filter
command = 24 --	View enemies only filter
command = 26 -- View allies & enemies filter
command = 28 -- Rotate the camera left fast
command = 29 -- Rotate the camera right fast
command = 30 -- Rotate the camera up fast
command = 31 -- Rotate the camera down fast
command = 32 -- Rotate the camera left slow
command = 33 -- Rotate the camera right slow
command = 34 -- Rotate the camera up slow
command = 35 -- Rotate the camera down slow
command = 36 -- Return the camera to default position
command = 37 --	View zoom in fast
command = 38 -- View zoom out fast
command = 39 -- View zoom in slow
command = 40 -- View zoom out slow
command = 41 -- Pan the camera left
command = 42 -- Pan the camera right
command = 43 -- Pan the camera up
command = 44 -- Pan the camera down
command = 45 -- Pan the camera left slow
command = 46 -- Pan the camera right slow
command = 47 -- Pan the camera up slow
command = 48 -- Pan the camera down slow
command = 49 -- Disable panning the camera
command = 50 -- Allies chat
command = 51 -- Mission quit
command = 52 -- Suspend/resume model time
command = 53 -- Accelerate model time
command = 54 -- Step by step simulation when model time is suspended
command = 55 --	Take control in the track
command = 57 -- Common chat
command = 59 -- Altitude stabilization
command = 62 -- Autopilot
command = 63 -- Auto-thrust
command = 64 -- Power up
command = 65 -- Power down
command = 68 -- Gear
command = 69 -- Hook
command = 70 -- Pack wings
command = 71 -- Canopy
command = 72 -- Flaps
command = 73 -- Air brake
command = 74 -- Wheel brakes on
command = 75 -- Wheel brakes off
command = 76 -- Release drogue chute
command = 77 -- Drop snar
command = 78 -- Wingtip smoke
command = 79 -- Refuel on
command = 80 -- Refuel off
command = 81 -- Salvo
command = 82 -- Jettison weapons
command = 83 -- Eject
command = 84 -- Fire on
command = 85 -- Fire off
command = 86 -- Radar
command = 87 -- EOS
command = 88 -- Rotate the radar antenna left
command = 89 -- Rotate the radar antenna right
command = 90 -- Rotate the radar antenna up
command = 91 -- Rotate the radar antenna down
command = 92 -- Center the radar antenna
command = 93 -- Trim left
command = 94 -- Trim right
command = 95 -- Trim up
command = 96 -- Trim down
command = 97 -- Cancel trimming
command = 98 -- Trim the rudder left
command = 99 -- Trim the rudder right
command = 100 -- Lock the target
command = 101 -- Change weapon
command = 102 -- Change target
command = 103 -- MFD zoom in
command = 104 -- MFD zoom out
command = 105 -- Navigation mode   (value 1, 2, 3, 4 for navmode_none, navmode_route, navmode_arrival ,navmode_landing	)
command = 106 -- BVR mode
command = 107 -- VS	mode
command = 108 -- Bore mode
command = 109 -- Helmet mode
command = 110 -- FI0 mode
command = 111 -- A2G mode
command = 112 -- Grid mode
command = 113 -- Cannon
command = 114 -- Dispatch wingman - complete mission and RTB
command = 115 -- Dispatch wingman - complete mission and rejoin
command = 116 -- Dispatch wingman - toggle formation
command = 117 -- Dispatch wingman - join up formation
command = 118 -- Dispatch wingman - attack my target
command = 119 -- Dispatch wingman - cover my six
command = 120 -- Take off from ship
command = 121 -- Cobra
command = 122 -- Sound on/off
command = 123 -- Sound recording on
command = 124 -- Sound recording off
command = 125 -- View right mirror on
command = 126 -- View right mirror off
command = 127 -- View left mirror on
command = 128 -- View left mirror off
command = 129 -- Natural head movement view
command = 131 -- LSO view
command = 135 -- Weapon to target view
command = 136 -- Active jamming
command = 137 -- Increase details level
command = 138 -- Decrease details level
command = 139 -- Scan zone left
command = 140 -- Scan zone right
command = 141 -- Scan zone up
command = 142 -- Scan zone down
command = 143 -- Unlock target
command = 144 -- Reset master warning
command = 145 -- Flaps on
command = 146 -- Flaps off
command = 147 -- Air brake on
command = 148 -- Air brake off
command = 149 -- Weapons view
command = 150 -- Static objects view
command = 151 -- Mission targets view
command = 152 -- Info bar details
command = 155 -- Refueling boom
command = 156 -- HUD color selection
command = 158 -- Jump to terrain view
command = 159 -- Starts moving F11 camera forward
command = 160 -- Starts moving F11 camera backward
command = 161 -- Power up left engine
command = 162 -- Power down left engine
command = 163 -- Power up right engine
command = 164 -- Power down right engine
command = 169 -- Immortal mode
command = 175 -- On-board lights
command = 176 -- Drop snar once
command = 177 -- Default cockpit angle of view
command = 178 -- Jettison fuel tanks
command = 179 -- Wingmen commands panel
command = 180 -- Reverse objects switching in views
command = 181 -- Forward objects switching in views
command = 182 -- Ignore current object in views
command = 183 -- View all ignored objects in views again
command = 184 -- Padlock terrain point
command = 185 -- Reverse the camera
command = 186 -- Plane up
command = 187 -- Plane down
command = 188 -- Bank left
command = 189 -- Bank right
command = 190 -- Local camera rotation mode
command = 191 -- Decelerate model time
command = 192 -- Jump into the other plane
command = 193 -- Nose down
command = 194 -- Nose down end
command = 195 -- Nose up
command = 196 -- Nose up end
command = 197 -- Bank left
command = 198 -- Bank left end
command = 199 -- Bank right
command = 200 -- Bank right end
command = 201 -- Rudder left
command = 202 -- Rudder left end
command = 203 -- Rudder right
command = 204 -- Rudder right end
command = 205 -- View up right
command = 206 -- View down right
command = 207 -- View down left
command = 208 -- View up left
command = 209 -- View stop
command = 210 -- View up right slow
command = 211 -- View down right slow
command = 212 -- View down left slow
command = 213 -- View up left slow
command = 214 -- View stop slow
command = 215 -- Stop trimming
command = 226 -- Scan zone up right
command = 227 -- Scan zone down right
command = 228 -- Scan zone down left
command = 229 -- Scan zone up left
command = 230 -- Scan zone stop
command = 231 -- Radar antenna up right
command = 232 -- Radar antenna down right
command = 233 -- Radar antenna down left
command = 234 -- Radar antenna up left
command = 235 -- Radar antenna stop
command = 236 -- Save snap view angles
command = 237 -- Cockpit panel view toggle
command = 245 -- Coordinates units toggle
command = 246 -- Disable model time acceleration
command = 252 -- Automatic spin recovery
command = 253 -- Speed retention
command = 254 -- Easy landing
command = 258 -- Threat missile padlock
command = 259 -- All missiles padlock
command = 261 -- Marker state
command = 262 -- Decrease radar scan area
command = 263 -- Increase radar scan area
command = 264 -- Marker state plane
command = 265 -- Marker state rocket
command = 266 -- Marker state plane ship
command = 267 -- Ask AWACS home airbase
command = 268 -- Ask AWACS available tanker
command = 269 -- Ask AWACS nearest target
command = 270 -- Ask AWACS declare target
command = 271 -- Easy radar
command = 272 -- Auto lock on nearest aircraft
command = 273 -- Auto lock on center aircraft
command = 274 -- Auto lock on next aircraft
command = 275 -- Auto lock on previous aircraft
command = 276 -- Auto lock on nearest surface target
command = 277 -- Auto lock on center surface target
command = 278 -- Auto lock on next surface target
command = 279 -- Auto lock on previous surface target
command = 280 -- Change cannon rate of fire
command = 281 -- Change ripple quantity
command = 282 -- Change ripple interval
command = 283 -- Switch master arm
command = 284 -- Change release mode
command = 285 -- Change radar mode RWS/TWS
command = 286 -- Change RWR/SPO mode
command = 288 -- Flight clock reset
command = 289 -- Zoom in slow stop
command = 290 -- Zoom out slow stop
command = 291 -- Zoom in stop
command = 292 -- Zoom out stop
command = 295 -- View horizontal stop
command = 296 -- View vertical stop
command = 298 -- Jump to fly-by view
command = 299 -- Camera jiggle
command = 300 -- Cockpit illumination
command = 308 -- Change ripple interval down
command = 309 -- Engines start
command = 310 -- Engines stop
command = 311 -- Left engine start
command = 312 -- Right engine start
command = 313 -- Left engine stop
command = 314 -- Right engine stop
command = 315 -- Power on/off
command = 316 -- Altimeter pressure increase
command = 317 -- Altimeter pressure decrease
command = 318 -- Altimeter pressure stop
command = 321 -- Fast mouse in views
command = 322 -- Slow mouse in views
command = 323 -- Normal mouse in views
command = 326 -- HUD only view
command = 327 -- Recover my plane
command = 328 -- Toggle gear light Near/Far/Off
command = 331 -- Fast keyboard in views
command = 332 -- Slow keyboard in views
command = 333 -- Normal keyboard in views
command = 334 -- Zoom in for external views
command = 335 -- Stop zoom in for external views
command = 336 -- Zoom out for external views
command = 337 -- Stop zoom out for external views
command = 338 -- Default zoom in external views
command = 341 -- A2G combat view
command = 342 -- Camera view up-left
command = 343 -- Camera view up-right
command = 344 -- Camera view down-left
command = 345 -- Camera view down right
command = 346 -- Camera pan mode toggle
command = 347 -- Return the camera
command = 348 -- Trains/cars toggle
command = 349 -- Launch permission override
command = 350 -- Release weapon
command = 351 -- Stop release weapon
command = 352 -- Return camera base
command = 353 -- Camera view up-left slow
command = 354 -- Camera view up-right slow
command = 355 -- Camera view down-left slow
command = 356 -- Camera view down-right slow
command = 357 -- Drop flare once
command = 358 -- Drop chaff once
command = 359 -- Rear view
command = 360 -- Scores window
command = 386 -- PlaneStabPitchBank
command = 387 -- PlaneStabHbarBank
command = 388 -- PlaneStabHorizont
command = 389 -- PlaneStabHbar
command = 390 -- PlaneStabHrad
command = 391 -- Active IR jamming on/off
command = 392 -- Laser range-finder on/off
command = 393 -- Night TV on/off(IR or LLTV)
command = 394 -- Change radar PRF
command = 395 -- Keep F11 camera altitude over terrain
command = 396 -- SnapView0
command = 397 -- SnapView1
command = 398 -- SnapView2
command = 399 -- SnapView3
command = 400 -- SnapView4
command = 401 -- SnapView5
command = 402 -- SnapView6
command = 403 -- SnapView7
command = 404 -- SnapView8
command = 405 -- SnapView9
command = 406 -- SnapViewStop
command = 407 -- F11 view binocular mode
command = 408 -- PlaneStabCancel
command = 409 -- ThreatWarnSoundVolumeDown
command = 410 -- ThreatWarnSoundVolumeUp
command = 411 -- F11 binocular view laser range-finder on/off
command = 412 -- PlaneIncreaseBase_Distance
command = 413 -- PlaneDecreaseBase_Distance
command = 414 -- PlaneStopBase_Distance
command = 425 -- F11 binocular view IR mode on/off
command = 426 -- F8 view player targets / all targets
command = 427 -- Plane autopilot override on
command = 428 -- Plane autopilot override off
command = 429 -- Plane route autopilot on/off
command = 430 -- Gear up
command = 431 -- Gear down

To be continued...
--]]

--	LoEnableExternalFlightModel()   call one time in start
--	LoUpdateExternalFlightModel(binary_data)   update function


--LoGetHelicopterFMData()
-- return table with fm data
--{
--G_factor = {x,y,z }    in cockpit
--speed = {x,y,z}   center of mass ,body axis
--acceleration= {x,y,z}   center of mass ,body axis
--angular_speed= {x,y,z}   rad/s
--angular_acceleration= {x,y,z}   rad/s^2
--yaw    radians
--pitch    radians
--roll    radians
--}

--#ifndef  _EXTERNAL_FM_DATA_H
--#define  _EXTERNAL_FM_DATA_H

--struct external_FM_data
--{
--	double orientation_X[3];
--	double orientation_Y[3];
--	double orientation_Z[3];
--	double pos[3];

--	//

--	double velocity[3];
--	double acceleration[3];
--	double omega[3];
--};
-- #endif  _EXTERNAL_FM_DATA_H


-- you can export render targets via shared memory interface
-- using next functions
--        LoSetSharedTexture(name)          -- register texture with name "name"  to export
--        LoRemoveSharedTexture(name)   -- copy texture with name "name"  to named shared memory area "name"
--        LoUpdateSharedTexture(name)    -- unregister texture
--       texture exported like Windows BMP file
--      --------------------------------
--      |BITMAPFILEHEADER   |
--      |BITMAPINFOHEADER |
--      |bits                                  |
--      --------------------------------
--      sample textures   :  "mfd0"    -  full  SHKVAL screen
--                                      "mfd1"     -  ABRIS map screen
--                                      "mfd2"    - not used
--                                      "mfd3"    - not used
--                                      "mirrors" - mirrors



--~ ProductName: DCS
--~ FileVersion: 1.2.14.36041
--~ ProductVersion: 1.2.14.36041
--~ t = 0.000000
--~ Goto_point :
--~  point_num = 1 ,wpt_pos = (-324113.906250, 1018.000000 ,618735.250000) ,next 2 ll = (41.890641 , 41.654361) name= TURNPOINT
--~ Route points:
--~ point_num = 1 ,wpt_pos = (-324113.906250, 1018.000000 ,618735.250000) ,next 2 ll = (41.890641 , 41.654361)
--~ point_num = 2 ,wpt_pos = (-321035.718750, 518.000000 ,627192.437500) ,next 3 ll = (41.910345 , 41.758895)
--~ point_num = 3 ,wpt_pos = (-317957.531250, 18.000000 ,635649.687500) ,next 4 ll = (41.929946 , 41.863480)
--~ point_num = 4 ,wpt_pos = (-318339.750000, 18.000000 ,634511.812500) ,next -1 ll = (41.927599 , 41.849445)
--~ self ll = 42.346981 , 41.820520
--~ t = 0.500000
--~ Goto_point :
--~  point_num = 2 ,wpt_pos = (-256542.859375, 2000.000000 ,612742.875000) ,next -1 ll = (42.497716 , 41.665378) name= TURNPOINT
--~ Route points:
--~ self ll = 42.347474 , 41.820014
--~ t = 1.000000
--~ Goto_point :
--~  point_num = 2 ,wpt_pos = (-256542.859375, 2000.000000 ,612742.875000) ,next -1 ll = (42.497716 , 41.665378) name= TURNPOINT
--~ Route points:
--~ self ll = 42.347966 , 41.819509
--~ t = 1.500000
