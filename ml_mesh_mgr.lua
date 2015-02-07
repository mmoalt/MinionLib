-- Meshmanager , Handles the loading/saving/recording of meshes and wanted gamedata

-- TO USE/IMPLEMENT THIS MANAGER:
-- Set ml_mesh_mgr.parentWindow.Name 
-- Call ml_mesh_mgr.OnUpdate( tickcount ) from the main pulse
-- Add a button with ToggleMeshManager as event to open/close the window
-- Add a "GetMapID() callback, like : ml_mesh_mgr.GetMapID = function () return Player:GetMapID() end
-- Add a "GetMapName() callback, like : ml_mesh_mgr.GetMapName = function () return Player:GetMapName() end
-- Add a "GetPlayerPos() callback, like : ml_mesh_mgr.GetPlayerPos = function () return Player:GetPlayerPos() end
-- Set "ml_mesh_mgr.averagegameunitsize" to a avg radius of how fat the player is, this val is used for determining the radius around the player to search for markers
-- Set "ml_mesh_mgr.navData" to a table with world connection nodes

-- Auto-recording Markers:
-- 
 
-- Usefull functions:
-- ml_mesh_mgr.LoadNavMesh( meshname ) -> loads the wanted mesh by its filename
-- ml_mesh_mgr.SetDefaultMesh(mapid,mapname)  -> sets this mapname as default for the mapid
-- ml_mesh_mgr.RemoveDefaultMesh(mapid) -> removes the default for the mapid
 
 
 -- Default mesh "class" that holds all relevant mesh data
ml_mesh = inheritsFrom(nil)
function ml_mesh.Create()
	local newinst = inheritsFrom( ml_mesh )
	newinst.MapID = 0					-- holds the current MapID
	newinst.AllowedMapIDs = {}			-- holds a list of MapIDs where this mesh is allowed to be used
	newinst.Name = ""					-- meshname / filename
	newinst.MarkerList = {}				-- not used yet, in future for holding the mesh marker data
	newinst.Obstacles = {}				-- not used yet, in future for holding the mesh obstacles
	newinst.AvoidanceAreas = {}			-- not used yet, in future for holding the mesh avoidanceareas
	newinst.LastPlayerPosition = { x=0, y=0, z=0, h=0, hx=0, hy=0, hz=0}	-- for autorecording markers n such
	return newinst
end

ml_mesh_mgr = { }
ml_mesh_mgr.navmeshfilepath = GetStartupPath() .. [[\Navigation\]];
ml_mesh_mgr.mainwindow = { name = GetStringML("meshManager"), x = 350, y = 100, w = 275, h = 400}
ml_mesh_mgr.parentWindow = { Name = "MinionBot" } -- Needs to get re-set
ml_mesh_mgr.navData = {} -- Holds the data for world navigation
ml_mesh_mgr.GetMapID = function () return 0 end -- Needs to get re-set
ml_mesh_mgr.GetMapName = function () return "NoName" end -- Needs to get re-set
ml_mesh_mgr.GetPlayerPos = function () return { x=0, y=0, z=0, h=0 } end -- Needs to get re-set
ml_mesh_mgr.SetEvacPoint = function () return 0 end -- Needs to get set
ml_mesh_mgr.nextNavMesh = nil -- Holds the navmeshfilename that should get loaded
ml_mesh_mgr.currentMesh = ml_mesh.Create()
ml_mesh_mgr.loadingMesh = false
ml_mesh_mgr.loadObjectFile = false
ml_mesh_mgr.averagegameunitsize = 50
ml_mesh_mgr.OMC = 0
ml_mesh_mgr.transitionthreshold = 10 -- distance when to autoset an OMC, like when we we'r walking though a portal or door but are still in the same map


-- GUI Init
function ml_mesh_mgr.ModuleInit()
	
	if (Settings.minionlib.DefaultMaps == nil) then
		Settings.minionlib.DefaultMaps = { }
	end
	Settings.minionlib.gNoMeshLoad = Settings.minionlib.gNoMeshLoad or "0"
	
	GUI_NewWindow(ml_mesh_mgr.mainwindow.name,ml_mesh_mgr.mainwindow.x,ml_mesh_mgr.mainwindow.y,ml_mesh_mgr.mainwindow.w,ml_mesh_mgr.mainwindow.h)
	GUI_NewComboBox(ml_mesh_mgr.mainwindow.name,GetStringML("navmesh"),"gmeshname",GetStringML("generalSettings"),"")
	GUI_NewCheckbox(ml_mesh_mgr.mainwindow.name,GetStringML("noMeshLoad"),"gNoMeshLoad",GetStringML("generalSettings"))
	GUI_NewCheckbox(ml_mesh_mgr.mainwindow.name,GetStringML("showrealMesh"),"gShowRealMesh",GetStringML("generalSettings"))
	GUI_NewCheckbox(ml_mesh_mgr.mainwindow.name,GetStringML("showMesh"),"gShowMesh",GetStringML("generalSettings"))
	GUI_NewCheckbox(ml_mesh_mgr.mainwindow.name,GetStringML("showPath"),"gShowPath",GetStringML("generalSettings"))
	GUI_UnFoldGroup(ml_mesh_mgr.mainwindow.name,GetStringML("generalSettings"))	
	GUI_NewButton(ml_mesh_mgr.mainwindow.name, GetStringML("setEvacPoint"), "ml_mesh_mgr.SetEvacPoint",GetStringML("recoder"))

	GUI_NewField(ml_mesh_mgr.mainwindow.name,GetStringML("newMeshName"),"gnewmeshname",GetStringML("recoder"))
	GUI_NewButton(ml_mesh_mgr.mainwindow.name,GetStringML("newMesh"),"newMeshEvent",GetStringML("recoder"))
	RegisterEventHandler("newMeshEvent",ml_mesh_mgr.ClearNavMesh)
	GUI_NewCheckbox(ml_mesh_mgr.mainwindow.name,GetStringML("recmesh"),"gMeshrec",GetStringML("recoder"))
	GUI_NewComboBox(ml_mesh_mgr.mainwindow.name,GetStringML("recAreaType"),"gRecAreaType",GetStringML("recoder"),"Road,Lowdanger,Highdanger")-- enum 1,2,3
	GUI_NewNumeric(ml_mesh_mgr.mainwindow.name,GetStringML("recAreaSize"),"gRecAreaSize",GetStringML("recoder"),"1","25")
	GUI_NewCheckbox(ml_mesh_mgr.mainwindow.name,GetStringML("changeMesh"),"gMeshChange",GetStringML("editor"))
	GUI_NewComboBox(ml_mesh_mgr.mainwindow.name,GetStringML("changeAreaType"),"gChangeAreaType",GetStringML("editor"),"Delete,Road,Lowdanger,Highdanger")
	GUI_NewNumeric(ml_mesh_mgr.mainwindow.name,GetStringML("changeAreaSize"),"gChangeAreaSize",GetStringML("editor"),"1","10")
	GUI_NewCheckbox(ml_mesh_mgr.mainwindow.name,GetStringML("biDirOffMesh"),"gBiDirOffMesh",GetStringML("connections"))
	GUI_NewComboBox(ml_mesh_mgr.mainwindow.name,GetStringML("typeOffMeshSpot"),"gOMCType",GetStringML("connections"),"Jump,Interact,Teleport,Portal")	
	--GUI_NewComboBox(ml_mesh_mgr.mainwindow.name,GetStringML("typeOffMeshSpot"),"gOMCType",GetStringML("connections"),"Jump")	
	GUI_NewButton(ml_mesh_mgr.mainwindow.name,GetStringML("addOffMeshSpot"),"offMeshSpotEvent",GetStringML("connections"))
	RegisterEventHandler("offMeshSpotEvent", ml_mesh_mgr.AddOMC)
	GUI_NewButton(ml_mesh_mgr.mainwindow.name,GetStringML("delOffMeshSpot"),"deleteoffMeshEvent",GetStringML("connections"))
	RegisterEventHandler("deleteoffMeshEvent", ml_mesh_mgr.DeleteOMC)
	
	GUI_NewButton(ml_mesh_mgr.mainwindow.name,GetStringML("createSingleCell"),"createSingleCell",GetStringML("recoder"))
	RegisterEventHandler("createSingleCell", ml_mesh_mgr.CreateSingleCell)
	
	GUI_NewButton(ml_mesh_mgr.mainwindow.name,GetStringML("saveMesh"),"saveMeshEvent") --GetStringML("editor"))
	RegisterEventHandler("saveMeshEvent",ml_mesh_mgr.SaveMesh)   
	
	--GUI_NewButton(ml_mesh_mgr.mainwindow.name,"CTRL+M:ChangeMeshRenderDepth","ChangeMeshDepth")
	
	
	GUI_SizeWindow(ml_mesh_mgr.mainwindow.name,ml_mesh_mgr.mainwindow.w,ml_mesh_mgr.mainwindow.h)
	GUI_WindowVisible(ml_mesh_mgr.mainwindow.name,false)
	
	gNoMeshLoad = Settings.minionlib.gNoMeshLoad
	gShowRealMesh = "0"
	gShowPath = "0"
	gShowMesh = "0"
	gnewmeshname = ""
	gMeshrec = "0"
	gRecAreaType = "Lowdanger"
	gRecAreaSize = "20"
	gMeshChange = "0"
	gChangeAreaType = "Road"
	gChangeAreaSize = "5"
	gBiDirOffMesh = "0"
	gOMCType = "Jump"
	
	if ( MeshManager ) then
		MeshManager:SetRecordingArea(2)
		MeshManager:RecSize(gRecAreaSize)
		MeshManager:SetChangeToArea(1)
		MeshManager:SetChangeToRadius(gChangeAreaSize)
		MeshManager:SetChangeAreaMode(false)
		MeshManager:Record(false)
		MeshManager:ShowTriMesh(false)
		NavigationManager:ShowNavMesh(false)
	end
	
	ml_mesh_mgr.loadingMesh = false
	ml_mesh_mgr.UpdateMeshfiles() --update the mesh-selection-dropdownfield
end

-- initializes the marker group, this needs to be called from the main.lua's HandleInit, after all possible marker templates were created or when templatelist was updated
ml_mesh_mgr.registeredevents = {} -- to prevent re-registering of the same events
function ml_mesh_mgr.InitMarkers()
	
	if ( ml_marker_mgr ) then		
		GUI_DeleteGroup(ml_mesh_mgr.mainwindow.name, GetStringML("markers"))
				
		-- create an ADD button for each type
		if ( ValidString(gMarkerMgrType_listitems) ) then 
			for mtype in StringSplit(gMarkerMgrType_listitems,",") do
										
				GUI_NewButton(ml_mesh_mgr.mainwindow.name,"New "..mtype,"ml_mesh_mgr.NewMarker_"..mtype,GetStringML("markers"))
				if ( not ml_mesh_mgr.registeredevents["ml_mesh_mgr.NewMarker_"..mtype] ) then
					RegisterEventHandler("ml_mesh_mgr.NewMarker_"..mtype,ml_mesh_mgr.HandleMarkerButtons)
					ml_mesh_mgr.registeredevents["ml_mesh_mgr.NewMarker_"..mtype] = 1
				end
			
			end
		end
		-- Select closest marker
		GUI_NewButton(ml_mesh_mgr.mainwindow.name,GetStringML("selectClosestMarker"),"ml_mesh_mgr.SelectClosestMarker",GetStringML("markers"))
		if ( not ml_mesh_mgr.registeredevents["ml_mesh_mgr.SelectClosestMarker"] ) then
			RegisterEventHandler("ml_mesh_mgr.SelectClosestMarker",ml_mesh_mgr.HandleMarkerButtons)
			ml_mesh_mgr.registeredevents["ml_mesh_mgr.SelectClosestMarker"] = 1
		end
		GUI_SizeWindow(ml_mesh_mgr.mainwindow.name,ml_mesh_mgr.mainwindow.w,ml_mesh_mgr.mainwindow.h)
	end
end
function ml_mesh_mgr.HandleMarkerButtons( event )
	
	if ( event == "ml_mesh_mgr.SelectClosestMarker") then
		-- Select Closest Marker
		local pPos = ml_mesh_mgr.GetPlayerPos()
		local closestMarker = ml_marker_mgr.GetClosestMarker( pPos.x, pPos.y, pPos.z, ml_mesh_mgr.averagegameunitsize*50)
		if ( closestMarker ) then
			gMarkerMgrType = closestMarker:GetType()
			ml_marker_mgr.CreateEditWindow(closestMarker)
		end
	else
		-- Create a new marker by type
		for mtype in StringSplit(event,"ml_mesh_mgr.NewMarker_") do
			
			if ( ValidString(gMarkerMgrType_listitems) ) then 
				for markertype in StringSplit(gMarkerMgrType_listitems,",") do
					if ( markertype == mtype ) then
						gMarkerMgrType = mtype
						ml_marker_mgr.currentEditMarker = nil
						ml_marker_mgr.NewMarker()
						break
					end
				end
			end
			
		end
	end
end


--Grab all meshfiles in our Navigation directory and update the mesh-selection-dropdownfield
function ml_mesh_mgr.UpdateMeshfiles()
	
	local meshlist = "none"	
	local meshfilelist = dirlist(ml_mesh_mgr.navmeshfilepath,".*obj")
	if ( TableSize(meshfilelist) > 0) then
		local i,meshname = next ( meshfilelist)
		while i and meshname do
			meshname = string.gsub(meshname, ".obj", "")
			meshlist = meshlist..","..meshname
			--d("Adding mesh to list : "..meshname)
			i,meshname = next ( meshfilelist,i)
		end
	end	
	gmeshname_listitems = meshlist
end

--Sets this mapname as default for the mapid if there is nothing set yet
--Automatically adds the mapid to the AllowedMapIDs[] in the .data file, so multiple maps/zones can use the same meshfile
function ml_mesh_mgr.SetDefaultMesh(mapid,mapname)
	if (tonumber(mapid) ~= nil and tonumber(mapid) ~= 0 and mapname ~= "" and mapname ~= "none" and mapname ~= "None" ) then
		if ( Settings.minionlib.DefaultMaps[mapid] == nil or Settings.minionlib.DefaultMaps[mapid] == "" or Settings.minionlib.DefaultMaps[mapid] == "none" or Settings.minionlib.DefaultMaps[mapid] == "None") then
			Settings.minionlib.DefaultMaps[mapid] = mapname
			Settings.minionlib.DefaultMaps = Settings.minionlib.DefaultMaps -- trigger saving of settings
			d( "New DEFAULT mesh "..mapname.." set for mapID "..tostring(mapid))
		end
		
		-- Updating the .data file
		if ( ml_mesh_mgr.navmeshfilepath ~= nil and ml_mesh_mgr.navmeshfilepath ~= "" ) then
			
			if (FileExists(ml_mesh_mgr.navmeshfilepath..mapname..".data")) then					
				local tmpMesh = ml_mesh.Create()
				tmpMesh = persistence.load(ml_mesh_mgr.navmeshfilepath..mapname..".data")
				if (not ValidTable(tmpMesh)) then
					d("Error setting default mesh, no valid ml_mesh table in loaded .data file!")					
				
				else
					-- have to add the new table to existing "old" ml_mesh table
					if ( not tmpMesh.AllowedMapIDs ) then
						tmpMesh.AllowedMapIDs = {}
					end
					-- adding the mapid to the allowedmapid table and saving it
					if ( tmpMesh.AllowedMapIDs[mapid] == nil ) then						
						tmpMesh.AllowedMapIDs[mapid] = mapid
						persistence.store(ml_mesh_mgr.navmeshfilepath..mapname..".data", tmpMesh)
						d(" Added MapID "..tostring(mapid).." to the AllowedMapIDs table of "..mapname)
						
						-- if the mapid is our current mapid then the current mesh table needs to be updated 
						-- otherwise it will double load the mesh
						if (tmpMesh.Name == ml_mesh_mgr.currentMesh.Name) then
							ml_mesh_mgr.currentMesh = tmpMesh
						end
					end
				end
			else
				-- creating a new .data file since it doesnt exist
				d( "WARNING: no .data file found for setting the default mesh: "..mapname.." with mapID: "..tostring(mapid))				
				local tmpMesh = ml_mesh.Create()
				tmpMesh.AllowedMapIDs[mapid] = mapid
				tmpMesh.MapID = mapid
				tmpMesh.Name = mapname				
				persistence.store(ml_mesh_mgr.navmeshfilepath..mapname..".data", tmpMesh)
				d( "Info: Created new default .data file for setting the default mesh: "..mapname.." with mapID: "..tostring(mapid))
			end
		else
		
			d( "Error setting default mesh: navmeshfilepath is nil or empty!")
		end
		
	else
		d( "Error setting default mesh, mapID or name invalid! : "..tostring(mapid).." / "..mapname)
	end	
end
--Updates the mapname as default for the mapid
function ml_mesh_mgr.UpdateDefaultMesh(mapid,mapname)
	if (tonumber(mapid) ~= nil and tonumber(mapid) ~= 0 and mapname ~= "" and mapname ~= "none" and mapname ~= "None" ) then
		if ( Settings.minionlib.DefaultMaps[mapid] ~= mapname ) then
			Settings.minionlib.DefaultMaps[mapid] = mapname
			Settings.minionlib.DefaultMaps = Settings.minionlib.DefaultMaps -- trigger saving of settings
			d( "Updating DEFAULT mesh "..mapname.." set for mapID "..tostring(mapid))
		end
	else
		d( "Error setting default mesh, mapID or name invalid! : "..tostring(mapid).." / "..mapname)
	end	
end
--Removes this mapname as default for the mapid
function ml_mesh_mgr.RemoveDefaultMesh(mapid)
	if (tonumber(mapid) ~= nil and tonumber(mapid) ~= 0 ) then		
		Settings.minionlib.DefaultMaps[mapid] = nil
		Settings.minionlib.DefaultMaps = Settings.minionlib.DefaultMaps -- trigger saving of settings		
	end	
end

-- Use this to load a new / wanted navmesh
-- Use this to load a new / wanted navmesh
function ml_mesh_mgr.LoadNavMesh( meshname )
	if ( meshname ~= nil and meshname ~= 0 and type(meshname) == "string") then
		if ( ml_mesh_mgr.loadingMesh == false ) then
			ml_mesh_mgr.nextNavMesh = meshname
			return true
		else
			d("Meshloading still in progress, cannot switch to new navmesh yet..")
		end		
	end
	return false
end

-- Handles the loading of navmeshes and markerdata when switching maps/meshes, gets called on each OnUpdate()
function ml_mesh_mgr.SwitchNavmesh()

	if (gNoMeshLoad == "1") then
		return false
	end
	
	if ( ml_mesh_mgr.nextNavMesh ~= nil and ml_mesh_mgr.nextNavMesh ~= "" ) then
		
		if ( ml_mesh_mgr.navmeshfilepath ~= nil and ml_mesh_mgr.navmeshfilepath ~= "" ) then
			-- Check if the file exist
			d("Loading Navmesh : " ..ml_mesh_mgr.nextNavMesh)
			if (not NavigationManager:LoadNavMesh(ml_mesh_mgr.navmeshfilepath..ml_mesh_mgr.nextNavMesh,ml_mesh_mgr.loadObjectFile)) then
				ml_error("Error while trying to load Navmesh: "..ml_mesh_mgr.navmeshfilepath..ml_mesh_mgr.nextNavMesh)
				ml_marker_mgr.ClearMarkerList()
				ml_marker_mgr.RefreshMarkerNames()
				gmeshname = ""
				gnewmeshname = ""
				
			else
				-- Dont reload the obj file again
				ml_mesh_mgr.loadObjectFile = false
				-- To prevent (re-)loading or saving of mesh data while the mesh is beeing build/loaded
				ml_mesh_mgr.loadingMesh = true
				
				-- Update MarkerData from .info file
				ml_marker_mgr.ClearMarkerList()
				
				if (FileExists(ml_mesh_mgr.navmeshfilepath..ml_mesh_mgr.nextNavMesh..".info")) then					
					ml_marker_mgr.ReadMarkerFile(ml_mesh_mgr.navmeshfilepath..ml_mesh_mgr.nextNavMesh..".info")            			
					ml_marker_mgr.DrawMarkerList()
					ml_marker_mgr.RefreshMarkerNames()					
				else
					d("Creating new marker file for "..ml_mesh_mgr.nextNavMesh)
					ml_marker_mgr.markerPath = ml_mesh_mgr.navmeshfilepath..ml_mesh_mgr.nextNavMesh..".info" -- this needs to be set, else the markermanager doesnt work when there is no .info file..should probably be fixed on markermanager side and not here
					ml_marker_mgr.WriteMarkerFile(ml_marker_mgr.markerPath)
					if (not FileExists(ml_mesh_mgr.navmeshfilepath..ml_mesh_mgr.nextNavMesh..".info")) then
						ml_error("Marker file creation failed.")
					end
				end				
				
				-- Update MeshData from .data file
				if (FileExists(ml_mesh_mgr.navmeshfilepath..ml_mesh_mgr.nextNavMesh..".data")) then					
					ml_mesh_mgr.currentMesh = persistence.load(ml_mesh_mgr.navmeshfilepath..ml_mesh_mgr.nextNavMesh..".data")
					if (not ValidTable(ml_mesh_mgr.currentMesh)) then
						ml_mesh_mgr.currentMesh = ml_mesh.Create()						
						d("WARNING: while loading meshdata-file from "..ml_mesh_mgr.navmeshfilepath..ml_mesh_mgr.nextNavMesh..".data")					
						ml_mesh_mgr.currentMesh.MapID = ml_mesh_mgr.GetMapID()
						ml_mesh_mgr.currentMesh.AllowedMapIDs[ml_mesh_mgr.currentMesh.MapID] = ml_mesh_mgr.currentMesh.MapID						
						ml_mesh_mgr.currentMesh.Name = ml_mesh_mgr.GetMapName()
						
					else
						-- check if the loaded currentMesh.mapID is good 
						if ( ml_mesh_mgr.currentMesh.MapID == 0 ) then
							ml_error("WARNING: Loaded Navmesh has no MapID:"..tostring(ml_mesh_mgr.currentMesh.MapID))
							d(" Removing the default mesh for this zone from our Defaultmap-list")
							ml_mesh_mgr.RemoveDefaultMesh(ml_mesh_mgr.GetMapID())
						end
						
						-- check if ml_mesh_mgr.currentMesh.MapID is our mapID
						if ( ml_mesh_mgr.currentMesh.MapID ~= ml_mesh_mgr.GetMapID() ) then
							ml_debug("WARNING: Loaded Navmesh MapID ~= current MapID() -> wrong NavMesh for this zone loaded ?")
						end
						
						-- adding the AllowedMapIDs table to "old" .info files
						if ( not ml_mesh_mgr.currentMesh.AllowedMapIDs ) then
							ml_mesh_mgr.currentMesh.AllowedMapIDs = {}
							if ( ml_mesh_mgr.currentMesh.MapID ~= 0 ) then
								ml_mesh_mgr.currentMesh.AllowedMapIDs[ml_mesh_mgr.currentMesh.MapID] = ml_mesh_mgr.currentMesh.MapID
							end
						end
												
						-- check if the loaded ml_mesh_mgr.currentMesh.AllowedMapIDs contains our current mapID which we are in
						if ( ml_mesh_mgr.currentMesh.AllowedMapIDs[ml_mesh_mgr.GetMapID()] == nil ) then
							ml_debug("WARNING: Loaded Navmesh AllowedMapIDs dont contain current MapID -> wrong NavMesh for this zone loaded ?")
							
							-- This can cause a "allowed" for each wrong selected meshfile in the mesh-dropdown field.
							ml_mesh_mgr.SetDefaultMesh(ml_mesh_mgr.GetMapID(), ml_mesh_mgr.nextNavMesh)
						end
						
					end
				else
					d("WARNING: ml_mesh_mgr.SwitchNavmesh: No Data-file exist : "..ml_mesh_mgr.navmeshfilepath..ml_mesh_mgr.nextNavMesh..".data")
					ml_mesh_mgr.currentMesh = ml_mesh.Create()					
					ml_mesh_mgr.currentMesh.MapID = ml_mesh_mgr.GetMapID()
					ml_mesh_mgr.currentMesh.AllowedMapIDs[ml_mesh_mgr.currentMesh.MapID] = ml_mesh_mgr.currentMesh.MapID
					ml_mesh_mgr.currentMesh.Name = ml_mesh_mgr.GetMapName()
				end				
				
				
				gmeshname = ml_mesh_mgr.nextNavMesh
				ml_mesh_mgr.nextNavMesh = nil			
				return true
			end			
		else
			ml_error("ml_mesh_mgr.SwitchNavmesh: navmeshfilepath is empty!")
		end
		ml_mesh_mgr.nextNavMesh = nil
	end
	
	return false
end

-- Loads the last used navmesh for the current map
function ml_mesh_mgr.LoadNavMeshForCurrentMap()
	-- Load Last/Default Navmesh for this MapID
	ml_mesh_mgr.nextNavMesh = Settings.minionlib.DefaultMaps[tonumber(ml_mesh_mgr.GetMapID())]	
				
	if ( ml_mesh_mgr.SwitchNavmesh() == false ) then		
	-- Init New Navmesh for this MapID		
		d("No default Navmesh found for this map, Initializing a new NavMesh")
		ml_mesh_mgr.ClearNavMesh()
	end
end

-- Main loop
function ml_mesh_mgr.OnUpdate( tickcount )
	local navstate = NavigationManager:GetNavMeshState()
	
	if ( ml_mesh_mgr.loadingMesh or 
		navstate == GLOBAL.MESHSTATE.MESHBUILDING or 
		ml_mesh_mgr.GetMapID() == nil or 
		ml_mesh_mgr.GetMapID() == 0 or 
		ml_mesh_mgr.SwitchNavmesh() == true ) 
	then 
		return 
	end
	
	-- Log Info
	if ( navstate == GLOBAL.MESHSTATE.MESHEMPTY ) then
		ml_debug("WARNING: NO NAVMESH LOADED! -> SELECT A NAVMESH IN THE MESHMANAGER FOR THIS ZONE")
	elseif ( navstate == GLOBAL.MESHSTATE.MESHREADY ) then
		if ( not Player.onmesh ) then			
			ml_debug("WARNING: PLAYER IS NOT STANDING ON THE NAVMESH! ")
		end
	end
	
	-- Init default mesh	
	if ( ml_mesh_mgr.currentMesh.MapID == 0 ) then
		ml_mesh_mgr.LoadNavMeshForCurrentMap()		
	else
	-- Check for changed MapID
		if ( ml_mesh_mgr.currentMesh.MapID ~= ml_mesh_mgr.GetMapID() and ml_mesh_mgr.currentMesh.AllowedMapIDs[ml_mesh_mgr.GetMapID()] == nil and gNoMeshLoad == "0") then
										
			d("MAP/ZONE CHANGED")
			
			-- save old meshdata if meshrecorder is active			
			if ( gMeshrec == "1" ) then
			
				-- Save MapMarker on "old" map/mesh
				--if ( ml_mesh_mgr.currentMesh.LastPlayerPosition.x ~= 0 and ml_marker_mgr.GetClosestMarker( ml_mesh_mgr.currentMesh.LastPlayerPosition.x, ml_mesh_mgr.currentMesh.LastPlayerPosition.y, ml_mesh_mgr.currentMesh.LastPlayerPosition.z, 5, GetStringML("mapMarker")) == nil and NavigationManager:IsOnMesh(ml_mesh_mgr.currentMesh.LastPlayerPosition) ) then
				if ( ml_mesh_mgr.currentMesh.LastPlayerPosition.x ~= 0 and ml_marker_mgr.GetClosestMarker( ml_mesh_mgr.currentMesh.LastPlayerPosition.x, ml_mesh_mgr.currentMesh.LastPlayerPosition.y, ml_mesh_mgr.currentMesh.LastPlayerPosition.z, 5) == nil ) then
					
					if ( not NavigationManager:IsOnMesh(ml_mesh_mgr.currentMesh.LastPlayerPosition) ) then
						ml_error(" Last position of Player in the last map was NOT on the mesh!")
					end
					
					-- Add MapMarker in mesh
					local newMarker = ml_marker:Create("MapMarker")
					newMarker:SetType(GetStringML("mapMarker"))
					newMarker:AddField("int", "Target MapID", ml_mesh_mgr.GetMapID())
					newMarker:SetName(tostring(ml_mesh_mgr.currentMesh.Name).." to "..tostring(ml_mesh_mgr.GetMapName()))
					if ( ml_marker_mgr.GetMarker(newMarker:GetName()) ~= nil ) then
						--add a random number onto the name until the string is unique
						local name = ""
						local tries = 0
						repeat
							name = newMarker:GetName()..tostring(tries)
							-- just a little check here to ensure we never get stuck in an infinite loop
							-- if somehow some idiot has the same marker name with 1-99 already
							tries = tries + 1
						until ml_marker_mgr.GetMarker(name) == nil or tries > 99
						newMarker:SetName(name)
					end
					newMarker:SetPosition(ml_mesh_mgr.currentMesh.LastPlayerPosition)
					ml_marker_mgr.AddMarker(newMarker)
					ml_marker_mgr.RefreshMarkerNames()	
					
				end
				-- Save the mesh from the last map				
				ml_mesh_mgr.SaveMesh()				
				return
			end
						
			-- load new mesh
			
			ml_mesh_mgr.LoadNavMeshForCurrentMap()			
			
		else			
			-- update currentmeshdata position
			local myPos = ml_mesh_mgr.GetPlayerPos()
			if (ValidTable(myPos)) then
				ml_mesh_mgr.currentMesh.LastPlayerPosition = {				
					x = myPos.x, 
					y = myPos.y, 
					z = myPos.z, 
					h = myPos.h 
				}
			end
			
			--Left Alt + Right Mouse
			if ( MeshManager:IsKeyPressed(164) and MeshManager:IsKeyPressed(2)) then
				local mousepos = MeshManager:GetMousePos()
				if ( TableSize(mousepos) > 0 ) then	
					if (MeshManager:DeleteRasterTriangle(mousepos)) then
						d("Deletion was successful.")
					end
				end
			end	
			
			if ( gMeshrec == "0" and gMeshChange == "0" and  MeshManager:IsKeyPressed(162) and MeshManager:IsKeyPressed(2)) then
				ml_mesh_mgr.CreateSingleCell()
			end	
			
			-- Record Mesh & Gamedata
			if ( gMeshrec == "1" or gMeshChange == "1") then
				-- Key-Input-Handler
				-- 162 = Left CTRL + Left Mouse
				if ( MeshManager:IsKeyPressed(162) and MeshManager:IsKeyPressed(1)) then --162 is the integervalue of the virtualkeycode (hex)

					MeshManager:RecForce(true)
				else
					MeshManager:RecForce(false)
				end			
				
				-- 162 = Left CTRL 
				if ( MeshManager:IsKeyPressed(162) ) then --162 is the integervalue of the virtualkeycode (hex)
					-- show the mesh if it issnt shown
					if ( gShowMesh == "0" ) then
						MeshManager:ShowTriMesh(true)
					end
					MeshManager:RecSteeper(true)
				else
					if ( gShowMesh == "0" ) then
						MeshManager:ShowTriMesh(false)
					end
					MeshManager:RecSteeper(false)
				end
				
				-- 160 = Left Shift
				if ( MeshManager:IsKeyPressed(160) ) then
					MeshManager:RecSize(2*tonumber(gRecAreaSize))
				else
					MeshManager:RecSize(tonumber(gRecAreaSize))
				end		 
			end
			
		end
	end	
end

function ml_mesh_mgr.SaveMesh()
	if ( ml_mesh_mgr.loadingMesh == false ) then
		
		d("Preparing to save NavMesh...")	
		local rec = gMeshrec
		gMeshrec = "0"
		gMeshChange = "0"		
		MeshManager:Record(false)
		MeshManager:SetChangeAreaMode(false)
		MeshManager:ShowTriMesh(false)
		NavigationManager:ShowNavMesh(false)
		
		local filename = ""
		-- If a new Meshname is given, create a new file and save it in there
		if ( gnewmeshname ~= nil and gnewmeshname ~= "" ) then
			-- Make sure file doesnt exist
			local found = false
			local meshfilelist = dirlist(ml_mesh_mgr.navmeshfilepath,".*obj")
			if ( TableSize(meshfilelist) > 0) then
				local i,meshname = next ( meshfilelist)
				while i and meshname do
					meshname = string.gsub(meshname, ".obj", "")
					if (meshname == gnewmeshname) then
						d("Mesh with that Name exists already...")
						found = true
						break
					end
					i,meshname = next ( meshfilelist,i)
				end
			end
			if ( not found) then
				-- add new file to list
				gmeshname_listitems = gmeshname_listitems..","..gnewmeshname
			end
			filename = gnewmeshname
			
		-- Else we save it under the selected name
		elseif (gmeshname ~= nil and gmeshname ~= "" and gmeshname ~= "none") then
			filename = gmeshname
		end	
		
		if ( filename ~= "" and filename ~= "none" ) then
			
			d("Saving NavMesh : "..filename)		
			if (NavigationManager:SaveNavMesh(filename)) then
								
				-- Saving of Default Mesh				
				ml_mesh_mgr.UpdateDefaultMesh(ml_mesh_mgr.currentMesh.MapID,filename)
				
				-- Updating mapIDs (this has to be seperated, else the allowedmapids will get the map of the new zone when zoning while recording is on nad the "old" mesh is autosaved
				if ( rec == "1" ) then
					ml_mesh_mgr.currentMesh.AllowedMapIDs[ml_mesh_mgr.currentMesh.MapID] = ml_mesh_mgr.currentMesh.MapID
				else
					ml_mesh_mgr.currentMesh.AllowedMapIDs[ml_mesh_mgr.GetMapID()] = ml_mesh_mgr.GetMapID()
				end
				
				-- Save MeshData				
				d("Saving MeshData..")				
				ml_mesh_mgr.SaveMeshData(filename)
				
				-- Update UI
				gmeshname = ml_mesh_mgr.nextNavMesh				
				ml_mesh_mgr.currentMesh.MapID = 0 -- triggers the reloading of the default mesh
				
			else
				ml_error("While saving the current Navmesh: "..filename)
			end
			gnewmeshname = ""
			gmeshname = filename
		else
			ml_error("Enter a new Navmesh name!")
		end
	end
end
-- Saves the additional mesh data into to the data file
function ml_mesh_mgr.SaveMeshData(filename)
	persistence.store(ml_mesh_mgr.navmeshfilepath..filename..".data", ml_mesh_mgr.currentMesh)
end

-- Deletes the current meshdata and resets the meshmanagerdata
function ml_mesh_mgr.ClearNavMesh()
	-- Unload old Mesh
	NavigationManager:UnloadNavMesh()
		    
	-- Delete Markers
	ml_marker_mgr.ClearMarkerList()		
	ml_marker_mgr.RefreshMarkerNames()
						
	-- Create Default Meshdata
	ml_mesh_mgr.currentMesh = ml_mesh.Create()
	ml_mesh_mgr.currentMesh.MapID = ml_mesh_mgr.GetMapID()
	ml_mesh_mgr.currentMesh.AllowedMapIDs[ml_mesh_mgr.currentMesh.MapID] = ml_mesh_mgr.currentMesh.MapID
	ml_mesh_mgr.currentMesh.Name = ml_mesh_mgr.GetMapName()
	gnewmeshname = ml_mesh_mgr.currentMesh.Name or ""
	gmeshname = "none"
	d("Empty NavMesh created...")
end

-- GUI handler
function ml_mesh_mgr.GUIVarUpdate(Event, NewVals, OldVals)
	for k,v in pairs(NewVals) do
		if ( k == "gmeshname" and v ~= "") then
			if ( v ~= "none" ) then
				ml_mesh_mgr.UpdateDefaultMesh(ml_mesh_mgr.GetMapID(),v) -- 
				ml_mesh_mgr.currentMesh.MapID = 0 -- trigger reload of mesh
			else
				ml_mesh_mgr.ClearNavMesh()
			end
		elseif( k == "gShowRealMesh") then
			if (v == "1") then
				NavigationManager:ShowNavMesh(true)
			else
				NavigationManager:ShowNavMesh(false)
			end
		elseif( k == "gShowPath") then
			if (v == "1") then
				NavigationManager:ShowNavPath(true)
			else
				NavigationManager:ShowNavPath(false)
			end			
		elseif( k == "gShowMesh") then
			if (v == "1") then
				ml_mesh_mgr.LoadObjectFile()
				MeshManager:ShowTriMesh(true)
			else
				MeshManager:ShowTriMesh(false)
			end				
		elseif( k == "gMeshrec") then
			if (v == "1") then
				ml_mesh_mgr.LoadObjectFile()
				MeshManager:Record(true)
			else
				MeshManager:Record(false)
			end
		elseif( k == "gRecAreaType") then
			if (v == "Road") then
				MeshManager:SetRecordingArea(1)
			elseif (v == "Lowdanger") then
				MeshManager:SetRecordingArea(2)
			elseif (v == "Highdanger") then
				MeshManager:SetRecordingArea(3)
			end
		elseif( k == "gRecAreaSize") then
			MeshManager:RecSize(tonumber(gRecAreaSize))
		elseif( k == "gMeshChange") then
			if (v == "1") then
				ml_mesh_mgr.LoadObjectFile()
				MeshManager:SetChangeAreaMode(true)
			else
				MeshManager:SetChangeAreaMode(false)
			end
		elseif( k == "gChangeAreaType") then
			if (v == "Road") then
				MeshManager:SetChangeToArea(1)
			elseif (v == "Lowdanger") then
				MeshManager:SetChangeToArea(2)
			elseif (v == "Highdanger") then
				MeshManager:SetChangeToArea(3)
			elseif (v == "Delete") then	
				MeshManager:SetChangeToArea(255)
			end
		elseif( k == "gChangeAreaSize") then
			MeshManager:SetChangeToRadius(tonumber(gChangeAreaSize))
		elseif( k == "gnewmeshname" ) then
			ml_mesh_mgr.currentMesh.Name = v
		elseif( k == "gNoMeshLoad" ) then
			Settings.FFXIVMINION[tostring(k)] = v
		end
	end
end

-- Gets called when a navmesh is done loading/building
function ml_mesh_mgr.NavMeshUpdate()
	d("Mesh was loaded successfully!")
	gnewmeshname = ""
	ml_mesh_mgr.loadingMesh = false
	if ( gShowMesh == "1" ) then
		MeshManager:ShowTriMesh(true)
	end
	if ( gShowPath == "1" ) then
		NavigationManager:ShowNavPath(true)
	end
	if ( gShowRealMesh == "1" ) then
		NavigationManager:ShowNavMesh(true)
	end	
	if ( gMeshrec == "1" ) then
		MeshManager:Record(true)
	end
end

-- add offmesh connection
function ml_mesh_mgr.AddOMC()
	local pos = Player.pos
	
	ml_mesh_mgr.OMC = ml_mesh_mgr.OMC+1
	if (ml_mesh_mgr.OMC == 1 ) then
		ml_mesh_mgr.OMCP1 = pos
		ml_mesh_mgr.OMCP1.y = ml_mesh_mgr.OMCP1.y
	elseif (ml_mesh_mgr.OMC == 2 ) then
		ml_mesh_mgr.OMCP2 = pos
		ml_mesh_mgr.OMCP2.y = ml_mesh_mgr.OMCP2.y
		local omctype
		if ( gOMCType == "Jump" ) then
			omctype = 0
		elseif ( gOMCType == "Teleport" ) then
			omctype = 1
		elseif ( gOMCType == "Portal" ) then
			omctype = 2
		elseif ( gOMCType == "Interact" ) then
			omctype = 3
		end
		
		if ( gBiDirOffMesh == "0" ) then
			d(MeshManager:AddOffMeshConnection(ml_mesh_mgr.OMCP1,ml_mesh_mgr.OMCP2,false,omctype))
		else
			d(MeshManager:AddOffMeshConnection(ml_mesh_mgr.OMCP1,ml_mesh_mgr.OMCP2,true,omctype))
		end
		ml_mesh_mgr.OMC = 0
	end	
end
-- delete offmesh connection
function ml_mesh_mgr.DeleteOMC()
	local pos = Player.pos
	MeshManager:DeleteOffMeshConnection(pos)
	ml_mesh_mgr.OMC = 0
end

-- Handler for different OMC types
function ml_mesh_mgr.HandleOMC( event, OMCType ) 	
	d("OMC REACHED : "..tostring(OMCType))
	if (OMCType == "OMC_INTERACT") then
		Player:Stop()
		local newTask = ffxiv_mesh_interact.Create()
		ml_task_hub:Add(newTask, IMMEDIATE_GOAL, TP_IMMEDIATE)
	end
	--Player:StopMovement()	
end

function ml_mesh_mgr.CreateSingleCell()
	d("Creating a single cell outside the raster!")
	local pPos = Player.pos
	local newVertexCenter = { x=pPos.x, y=pPos.y, z=pPos.z }
	d(MeshManager:CreateSingleCell( newVertexCenter))
end

-- Toggle meshmanager Window
function ml_mesh_mgr.ToggleMenu()
    if (ml_mesh_mgr.visible) then
        GUI_WindowVisible(ml_mesh_mgr.mainwindow.name,false)
        ml_mesh_mgr.visible = false
    else
        local wnd = GUI_GetWindowInfo(ml_mesh_mgr.parentWindow.Name)
        if (wnd) then
            GUI_MoveWindow( ml_mesh_mgr.mainwindow.name, wnd.x+wnd.width,wnd.y) 
            GUI_WindowVisible(ml_mesh_mgr.mainwindow.name,true)
			GUI_SizeWindow(ml_mesh_mgr.mainwindow.name,ml_mesh_mgr.mainwindow.w,ml_mesh_mgr.mainwindow.h)
        end
        
        ml_mesh_mgr.visible = true
    end
end

-- load the obj file of the mesh for editing functions
function ml_mesh_mgr.LoadObjectFile()
	if ( gmeshname ~= "none" and not NavigationManager:IsObjectFileLoaded()) then
		d("Loading .OBJ file for mesh...")
		ml_mesh_mgr.loadObjectFile = true
		ml_mesh_mgr.LoadNavMesh(gmeshname)
	end
end

function ml_mesh_mgr.SetEvacPoint()
    if (gmeshname ~= "" and ml_global_information.Player_OnMesh ) then
        ml_marker_mgr.markerList["evacPoint"] = ml_global_information.Player_Position
        ml_marker_mgr.WriteMarkerFile(ml_marker_mgr.markerPath)
    end
end

function ml_mesh_mgr.SetupNavNodes()
    for id, neighbors in pairs(ml_mesh_mgr.navData) do
		local node = ml_node:Create()
		if (ValidTable(node)) then
			node.id = id
			for nid, posTable in pairs(neighbors) do
				node:AddNeighbor(nid, posTable)
			end
			ml_nav_manager.AddNode(node)
		end
	end
end

function ml_mesh_mgr.HandleButtons( Event, Button )	
	if ( Event == "GUI.Item" ) then
		if (string.find(Button,"ml_mesh_mgr.") ~= nil) then
			ExecuteFunction(Button)
		end
	end
end

RegisterEventHandler("GUI.Item",ml_mesh_mgr.HandleButtons )
RegisterEventHandler("ToggleMeshManager", ml_mesh_mgr.ToggleMenu)
RegisterEventHandler("GUI.Update",ml_mesh_mgr.GUIVarUpdate)
RegisterEventHandler("Module.Initalize",ml_mesh_mgr.ModuleInit)
RegisterEventHandler("Gameloop.MeshReady",ml_mesh_mgr.NavMeshUpdate)
RegisterEventHandler("Gameloop.OffMeshConnectionReached",ml_mesh_mgr.HandleOMC)
RegisterEventHandler("ChangeMeshDepth", function() RenderManager:ChangeMeshDepth() end)