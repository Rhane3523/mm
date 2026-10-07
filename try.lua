local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local localPlayer = Players.LocalPlayer

-- One owner for callbacks, jobs and UI. Re-execution disposes the previous run.
if type(_G.CartiHubShutdown) == "function" then
    pcall(_G.CartiHubShutdown)
end
-- Compatibility cleanup for runs from before a shutdown owner existed.
for _, root in ipairs({CoreGui, localPlayer:WaitForChild("PlayerGui")}) do
    for _, name in ipairs({"SakaModMenu", "CartiHubNebula", "CartiHubPlayerValuesGUI",
        "CartiHubBlockValueGUI", "CartiHubPlayerListBlockButtons", "CartiHubFriendJoinTopToast"}) do
        -- A game inventory callback may lower the caller's capability during
        -- the previous run's shutdown. Protected legacy CoreGui is optional.
        pcall(function()
            local old = root:FindFirstChild(name)
            if old then old:Destroy() end
        end)
    end
end
for _, state in ipairs({_G.CartiHubAutoTradeState or {}, _G.CartiHubBlockValueState or {}}) do state.Enabled = false end
local Runtime = {
    Active = true, Connections = {}, Jobs = {}, Guis = {}, Cleanups = {}, Queue = {},
    NativeTask = task, Exports = {}, Status = {},
}
function Runtime.cleanup(callback)
    table.insert(Runtime.Cleanups, callback)
end
function Runtime.schedule(mode, delaySeconds, callback, ...)
    if not Runtime.Active then return nil end
    local args = table.pack(...)
    local thread = coroutine.create(function()
        if Runtime.Active then
            local ok, err = xpcall(function() callback(table.unpack(args, 1, args.n)) end, debug.traceback)
            if not ok then warn("[Carti Hub] " .. tostring(err)) end
        end
        Runtime.Jobs[coroutine.running()] = nil
    end)
    Runtime.Jobs[thread] = true
    if mode == "delay" then Runtime.NativeTask.delay(delaySeconds, thread)
    else Runtime.NativeTask[mode](thread) end
    return thread
end
local task = {
    wait = Runtime.NativeTask.wait,
    spawn = function(fn, ...) return Runtime.schedule("spawn", nil, fn, ...) end,
    defer = function(fn, ...) return Runtime.schedule("defer", nil, fn, ...) end,
    delay = function(seconds, fn, ...) return Runtime.schedule("delay", seconds, fn, ...) end,
}
function Runtime.connect(signal, callback)
    local connection = signal:Connect(function(...)
        if Runtime.Active then table.insert(Runtime.Queue, {callback, table.pack(...)}) end
    end)
    Runtime.Connections[connection] = true
    return connection
end
function Runtime.ownGui(gui)
    if not Runtime.Active then gui:Destroy(); return gui end
    Runtime.Guis[gui] = true
    return gui
end
function Runtime.screenGui()
    return Runtime.ownGui(Instance.new("ScreenGui"))
end
function Runtime.shutdown()
    if not Runtime.Active then return end
    for key, value in pairs(_G) do
        if type(key) == "string" and key:match("^CartiHub") and type(value) == "function" then
            Runtime.Exports[key] = value
        end
    end
    Runtime.Active = false
    table.clear(Runtime.Queue)
    for connection in pairs(Runtime.Connections) do pcall(function() connection:Disconnect() end) end
    table.clear(Runtime.Connections)
    for thread in pairs(Runtime.Jobs) do
        if thread ~= coroutine.running() then pcall(Runtime.NativeTask.cancel, thread) end
    end
    table.clear(Runtime.Jobs)
    for index = #Runtime.Cleanups, 1, -1 do pcall(Runtime.Cleanups[index]) end
    for gui in pairs(Runtime.Guis) do pcall(function() gui:Destroy() end) end
    table.clear(Runtime.Guis)
    for key, value in pairs(Runtime.Exports) do if _G[key] == value then _G[key] = nil end end
    if _G.CartiHubRuntime == Runtime then _G.CartiHubRuntime = nil end
    if _G.CartiHubShutdown == Runtime.shutdown then _G.CartiHubShutdown = nil end
end
_G.CartiHubRuntime = Runtime
_G.CartiHubShutdown = Runtime.shutdown
-- Dispatch signals on this run's own executor-created thread. Game signal
-- callbacks can otherwise lose the capability needed to edit imported UI.
task.spawn(function()
    while Runtime.Active do
        local queue = Runtime.Queue
        Runtime.Queue = {}
        for _, event in ipairs(queue) do
            task.spawn(event[1], table.unpack(event[2], 1, event[2].n))
        end
        for connection in pairs(Runtime.Connections) do
            if not connection.Connected then Runtime.Connections[connection] = nil end
        end
        task.wait(0.03)
    end
end)

-- BEGIN NPC RUNTIME
-- Local scene actors. No Player spoofing, server chat, tools, or game remotes.
do
    local Pathfinding = game:GetService("PathfindingService")
    local TextService = game:GetService("TextService")
    local CollectionService = game:GetService("CollectionService")
    local rng = Random.new()
    local profiles = {
        {Name = "Relaxed", Speed = 11.8, Reaction = .65, Acceleration = 20, Turn = 5.5, Social = .55},
        {Name = "Curious", Speed = 13.2, Reaction = .38, Acceleration = 25, Turn = 6.5, Social = .8},
        {Name = "Energetic", Speed = 14.6, Reaction = .24, Acceleration = 30, Turn = 7.5, Social = .7},
    }
    -- Allocate styles from a shuffled bag so a group does not march in sync.
    local animationSets = {
        {Name="Classic", Idle=507766666, Idle2=507766951, Walk=507777826},
        {Name="Stylish", Idle=616136790, Idle2=616138447, Walk=616146177},
        {Name="Superhero", Idle=616111295, Idle2=616113536, Walk=616122287},
        {Name="Toy", Idle=782841498, Idle2=782845736, Walk=782843345},
        {Name="Ninja", Idle=656117400, Idle2=656118341, Walk=656121766},
        {Name="Pirate", Idle=750781874, Idle2=750782770, Walk=750785693},
    }
    local names = {"Nova", "milo", "Skyy", "luna", "Ash", "Kiki", "Riley", "Pixel", "Starri", "Theo", "Echo", "Remi"}
    local conversations = {
        {Context="Idle", "which map do you like most?", "the small ones are fun"},
        {Context="Idle", "anyone else always forget where they are", "every time lol"},
        {Context="Idle", "your outfit is nice", "ty :)"},
        {Context="Idle", "i like this spot", "yeah it's pretty quiet"},
        {Context="Idle", "one sec", "no rush"},
        {Context="Idle", "hi", "hey!"},
        {Context="Idle", "just taking a little break", "same here"},
        {Context="Idle", "what should we do next?", "let's look around"},
        {Context="Moving", "wait up", "coming"},
        {Context="Moving", "which way are we going?", "this way i think"},
        {Context="Moving", "i keep getting turned around", "same lol"},
        {Context="Moving", "hold on, catching up", "ok"},
        {Context="Moving", "this place is bigger than i thought", "yeah"},
        {Context="Moving", "are we going around again?", "just exploring"},
        {Context="Any", "hello :)", "hey"},
        {Context="Any", "how's it going?", "pretty good"},
        {Context="Any", "i'm still learning this map", "you'll get it"},
        {Context="Any", "nice avatar", "thanks!"},
        {Context="Any", "anyone know a good hiding spot?", "i'm still looking"},
        {Context="Any", "i always take the long way", "me too"},
    }
    local function flat(value) return Vector3.new(value.X,0,value.Z) end
    local function unit(value) return value.Magnitude>.001 and value.Unit or Vector3.zero end
    local function clipped(value,count)
        local str=tostring(value or ""):gsub("[%c]"," "):match("^%s*(.-)%s*$")
        if not utf8.len(str) then str=str:gsub("[\128-\255]","?") end
        local index=utf8.offset(str,count+1)
        return index and str:sub(1,index-1) or str
    end
    local function shuffle(list)
        for i=#list,2,-1 do local j=rng:NextInteger(1,i);list[i],list[j]=list[j],list[i] end
        return list
    end
    function Runtime.createNPCController(options)
        options = options or {}
        local npc = {
            Active = true, Records = {}, Pending = {}, Templates = {}, TemplateOrder = {},
            Generation = 0, Sequence = 0, PendingCount = 0, Limit = 20, Mode = "Follow", Spread = 9,
            ChatEnabled = true, NamesEnabled = true, Paused = false, ChatNext = os.clock() + 12,
            PathCount = 0, LastPathStart = 0, Connections = {}, Jobs = {}, LastError = nil,
            AnimationBag = {}, AvatarBag = {}, ChatPace = "Normal", Replies = {}, History = {}, FootstepsEnabled = true,
        }
        npc.Folder = Instance.new("Folder")
        npc.Folder.Name = "CartiHubNPCs"
        npc.Folder:SetAttribute("CartiHubLocalNPCs", true)
        npc.Folder.Parent = workspace
        local function alive() return npc.Active and Runtime.Active end
        local function schedule(fn)
            if not alive() then return end
            local thread = coroutine.create(function()
                local ok, err = xpcall(fn, debug.traceback)
                npc.Jobs[coroutine.running()] = nil
                Runtime.Jobs[coroutine.running()] = nil
                if not ok and alive() then npc.LastError = tostring(err); warn("[Carti NPC] " .. tostring(err)) end
            end)
            npc.Jobs[thread], Runtime.Jobs[thread] = true, true
            Runtime.NativeTask.spawn(thread)
            return thread
        end
        local function connect(signal, fn)
            local connection = Runtime.connect(signal, function(...) if alive() then fn(...) end end)
            npc.Connections[connection] = true
            return connection
        end
        local function playerRoot()
            if options.GetRoot then return options.GetRoot() end
            local character = localPlayer.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            return humanoid and humanoid.Health > 0 and character:FindFirstChild("HumanoidRootPart") or nil
        end
        local function changed()
            if npc.Changed then pcall(npc.Changed) end
        end
        function npc:Count()
            local n = 0; for _ in pairs(self.Records) do n += 1 end; return n
        end
        function npc:List()
            local list = {}; for _, record in pairs(self.Records) do table.insert(list, record) end
            table.sort(list, function(a,b) return a.Id < b.Id end); return list
        end
        function npc:RayParams()
            local now=os.clock()
            if self.QueryParams and now<(self.QueryExpires or 0) then return self.QueryParams end
            local ignored = {self.Folder}
            for _, player in ipairs(Players:GetPlayers()) do
                if player.Character then table.insert(ignored, player.Character) end
            end
            local params = RaycastParams.new()
            params.FilterType, params.FilterDescendantsInstances = Enum.RaycastFilterType.Exclude, ignored
            params.RespectCanCollide, params.IgnoreWater = true, true
            self.QueryParams,self.QueryExpires=params,now+.2
            return params
        end
        function npc:Ground(position, drop)
            local hit = workspace:Raycast(position + Vector3.new(0, 5, 0), Vector3.new(0, -(drop or 18), 0), self:RayParams())
            if hit and hit.Normal.Y > 0.55 then return hit.Position end
        end
        function npc:SafePosition(origin, radius)
            for attempt = 1, 24 do
                local angle = rng:NextNumber(0, math.pi * 2)
                local r = attempt <= 16 and rng:NextNumber(math.max(3, radius * 0.6), radius) or rng:NextNumber(2.5,math.max(3,radius*.65))
                local floor = self:Ground(origin + Vector3.new(math.cos(angle)*r, 0, math.sin(angle)*r), 22)
                if floor and math.abs(floor.Y - origin.Y) < 11 then
                    local free = true
                    for _, other in pairs(self.Records) do
                        if flat(other.Root.Position - floor).Magnitude < 4.2 then free = false; break end
                    end
                    if free then
                        local ceiling = workspace:Raycast(floor + Vector3.new(0, 0.3, 0), Vector3.new(0, 5.5, 0), self:RayParams())
                        if not ceiling then return floor end
                    end
                end
            end
            return nil
        end
        local function destroyPath(record)
            if record.PathConnection then record.PathConnection:Disconnect(); npc.Connections[record.PathConnection] = nil; record.PathConnection = nil end
            if record.Path then record.Path:Destroy(); record.Path = nil end
            record.Waypoints, record.Waypoint = nil, nil
        end
        function npc:Remove(record)
            if type(record) == "number" then record = self.Records[record] end
            if not record or record.Disposed then return end
            record.Disposed = true
            if self.ClearLoadout then pcall(self.ClearLoadout,self,record) end
            record.NavGeneration = (record.NavGeneration or 0) + 1
            self.Records[record.Id], self.Pending[record] = nil, nil
            if self.Selected == record then self.Selected = nil end
            destroyPath(record)
            if record.ComputingPath then record.ComputingPath:Destroy(); record.ComputingPath=nil end
            for _, connection in ipairs(record.Connections or {}) do connection:Disconnect(); self.Connections[connection] = nil end
            for _, track in pairs(record.Tracks or {}) do pcall(function() track:Stop(0); track:Destroy() end) end
            if record.Description then record.Description:Destroy(); record.Description = nil end
            if record.Model then record.Model:Destroy() end
            changed()
        end
        function npc:Clear()
            self.Generation += 1
            self.Batch = nil
            self.PendingCount = 0
            local pending = {}; for record in pairs(self.Pending) do table.insert(pending, record) end
            for _, record in ipairs(pending) do self:Remove(record) end
            for _, record in ipairs(self:List()) do self:Remove(record) end
            self.Reply, self.LastError = nil, nil
            table.clear(self.Replies);table.clear(self.History)
            changed()
        end
        function npc:Shutdown()
            if not self.Active then return end
            self.Active = false
            self:Clear()
            for connection in pairs(self.Connections) do connection:Disconnect(); Runtime.Connections[connection] = nil end
            for thread in pairs(self.Jobs) do
                if thread ~= coroutine.running() then pcall(Runtime.NativeTask.cancel, thread) end
                Runtime.Jobs[thread] = nil
            end
            for _, template in pairs(self.Templates) do template:Destroy() end
            table.clear(self.Templates); table.clear(self.Connections); table.clear(self.Jobs)
            self.Folder:Destroy()
        end
        function npc:ResolveAvatar(value)
            local str = tostring(value or ""):match("^%s*(.-)%s*$")
            if str == "" then
                local pool = Players:GetPlayers()
                table.sort(pool, function(a,b) return a.UserId < b.UserId end)
                local ids={};for _,player in ipairs(pool) do table.insert(ids,player.UserId) end
                local signature=table.concat(ids,",")
                if #self.AvatarBag==0 or self.AvatarSignature~=signature then
                    self.AvatarBag=shuffle(ids);self.AvatarSignature=signature
                end
                return table.remove(self.AvatarBag) or localPlayer.UserId
            end
            local id = tonumber(str)
            if id then assert(id > 0 and id % 1 == 0, "Enter a valid positive user ID."); return id end
            assert(str:match("^[%w_]+$") and #str <= 20, "Enter a username or user ID.")
            return Players:GetUserIdFromNameAsync(str)
        end
        function npc:LoadAvatar(userId, record)
            local template = self.Templates[userId]
            if template then return template:Clone() end
            local description = Players:GetHumanoidDescriptionFromUserIdAsync(userId)
            if record.Disposed or not alive() then description:Destroy(); error("Spawn cancelled.") end
            record.Description = description
            local ok, model = pcall(function() return Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15) end)
            description:Destroy(); record.Description = nil
            if not ok then error("Avatar could not load: " .. tostring(model)) end
            if record.Disposed or not alive() then model:Destroy(); error("Spawn cancelled.") end
            for _, item in ipairs(model:GetDescendants()) do
                for _, tag in ipairs(CollectionService:GetTags(item)) do CollectionService:RemoveTag(item, tag) end
                if item:IsA("LuaSourceContainer") or item:IsA("Tool") then item:Destroy() end
            end
            model.Archivable = true
            -- Concurrent same-avatar loads share a single cached template.
            if self.Templates[userId] then model:Destroy(); return self.Templates[userId]:Clone() end
            self.Templates[userId] = model; table.insert(self.TemplateOrder, userId)
            if #self.TemplateOrder > 12 then
                local evicted = table.remove(self.TemplateOrder, 1)
                self.Templates[evicted]:Destroy(); self.Templates[evicted] = nil
            end
            return model:Clone()
        end
        local function loadTrack(record, id, priority, looped)
            local animation = Instance.new("Animation"); animation.AnimationId = "rbxassetid://" .. id
            local ok, track = pcall(function() return record.Animator:LoadAnimation(animation) end)
            animation:Destroy()
            if ok then track.Priority, track.Looped = priority, looped; return track end
        end
        local function takeAnimationSet()
            if #npc.AnimationBag==0 then
                for _,set in ipairs(animationSets) do table.insert(npc.AnimationBag,set) end
                shuffle(npc.AnimationBag)
            end
            return table.remove(npc.AnimationBag)
        end
        local function noCollision(record, part)
            if not part:IsA("BasePart") then return end
            local constraint = Instance.new("NoCollisionConstraint")
            constraint.Part0, constraint.Part1, constraint.Parent = record.Root, part, record.CollisionFolder
        end
        function npc:BindPlayerCollisions(record)
            record.CollisionFolder:ClearAllChildren()
            local char = localPlayer.Character
            if char then for _, part in ipairs(char:GetDescendants()) do noCollision(record, part) end end
            for _, other in pairs(self.Records) do if other ~= record then noCollision(record, other.Root) end end
        end
        function npc:Spawn(avatar, displayName)
            if not alive() then return false, "NPC controller is closed." end
            if self:Count() + self.PendingCount >= self.Limit then return false, "Maximum 20 NPCs. Remove one before adding more." end
            if not playerRoot() then return false, "Wait for your character to spawn." end
            self.Sequence += 1; self.PendingCount += 1
            local generation = self.Generation
            local record = {Id = self.Sequence, Connections = {}, Tracks = {}, NavGeneration = 0, Generation = generation}
            self.Pending[record] = true; changed()
            local ok, err = xpcall(function()
                record.UserId = self:ResolveAvatar(avatar)
                assert(generation == self.Generation and not record.Disposed and alive(), "Spawn cancelled.")
                local model = self:LoadAvatar(record.UserId, record)
                if generation ~= self.Generation or record.Disposed or not alive() then model:Destroy(); error("Spawn cancelled.") end
                record.Model = model
                record.Root = assert(model:FindFirstChild("HumanoidRootPart"), "Avatar has no root.")
                record.Humanoid = assert(model:FindFirstChildOfClass("Humanoid"), "Avatar has no humanoid.")
                record.Head = assert(model:FindFirstChild("Head"), "Avatar has no head.")
                local root = assert(playerRoot(), "Wait for your character to spawn.")
                local floor = assert(self:SafePosition(root.Position, 8 + self:Count()*0.45), "No safe floor nearby. Move to an open area.")
                record.Name = clipped(displayName,24)
                if record.Name == "" then record.Name = names[(record.Id-1)%#names+1] .. tostring(rng:NextInteger(10,99)) end
                record.Profile = profiles[(record.Id-1)%#profiles+1]
                record.AnimationSet=takeAnimationSet()
                record.Speed = record.Profile.Speed + rng:NextNumber(-0.5,0.5)
                record.Phase, record.Angle = rng:NextNumber(0,10), rng:NextNumber(0,math.pi*2)
                record.Distance = rng:NextNumber(0.8,1.35)
                record.Side=(record.Id%2==0 and 1 or -1)*rng:NextNumber(.45,1.1)
                record.Back=rng:NextNumber(.65,1.2)
                record.Deadzone=rng:NextNumber(2,3.5)
                record.Velocity,record.AnimationsEnabled=Vector3.zero,true
                record.NextGaze,record.NextIdleStyle=os.clock()+rng:NextNumber(.5,2),os.clock()+rng:NextNumber(8,15)
                record.ChatNext=os.clock()+rng:NextNumber(5,16)
                record.NextJump,record.Recoveries=0,0
                record.NextDecision, record.NextIdle = os.clock()+rng:NextNumber(.2,1), os.clock()+rng:NextNumber(3,8)
                record.LastProgress, record.LastProgressAt, record.NextPath = floor, os.clock(), 0
                record.Home, record.Mode = floor, self.Mode
                record.Height = record.Humanoid.HipHeight + record.Root.Size.Y/2
                record.BodyRadius=math.clamp(math.max(record.Root.Size.X,record.Root.Size.Z)*.55,.75,1.3)
                model.Name, model.PrimaryPart = record.Name, record.Root
                model:SetAttribute("CartiHubLocalNPC", true); model:SetAttribute("AvatarUserId", record.UserId)
                record.Humanoid.DisplayName = record.Name
                record.Humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Subject
                record.Humanoid.NameDisplayDistance = self.NamesEnabled and 45 or 0
                record.Humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
                record.Humanoid.BreakJointsOnDeath = false
                record.Humanoid.AutoRotate, record.Humanoid.WalkSpeed = true, record.Speed
                for _, part in ipairs(model:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.Anchored, part.CanTouch, part.CanQuery = false, false, false
                        part.CanCollide, part.Massless = part == record.Root, part ~= record.Root
                    end
                end
                record.Root.Anchored = true
                model:PivotTo(CFrame.new(floor + Vector3.new(0,record.Height+0.1,0)) * root.CFrame.Rotation)
                record.CollisionFolder = Instance.new("Folder", model); record.CollisionFolder.Name = "LocalCollisionExclusions"
                self:BindPlayerCollisions(record)
                model.Parent = self.Folder
                record.Animator = record.Humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator",record.Humanoid)
                record.Tracks.Idle = loadTrack(record, record.AnimationSet.Idle, Enum.AnimationPriority.Idle, true)
                record.Tracks.Idle2 = loadTrack(record, record.AnimationSet.Idle2, Enum.AnimationPriority.Idle, true)
                record.Tracks.Walk = loadTrack(record, record.AnimationSet.Walk, Enum.AnimationPriority.Movement, true)
                record.Tracks.Jump = loadTrack(record, 507765000, Enum.AnimationPriority.Movement, false)
                record.Tracks.Fall = loadTrack(record, 507767968, Enum.AnimationPriority.Movement, true)
                record.Tracks.Wave = loadTrack(record, 507770239, Enum.AnimationPriority.Action, false)
                record.Tracks.Point = loadTrack(record, 507770453, Enum.AnimationPriority.Action, false)
                record.Tracks.Cheer = loadTrack(record, 507770677, Enum.AnimationPriority.Action, false)
                record.Tracks.Laugh = loadTrack(record, 507770818, Enum.AnimationPriority.Action, false)
                record.Footsteps=Instance.new("Sound",record.Root)
                record.Footsteps.Name,record.Footsteps.SoundId="NPCFootsteps","rbxasset://sounds/action_footsteps_plastic.mp3"
                record.Footsteps.Looped,record.Footsteps.Volume=true,.12
                record.Footsteps.RollOffMinDistance,record.Footsteps.RollOffMaxDistance=3,28
                record.Footsteps.RollOffMode=Enum.RollOffMode.InverseTapered
                record.Neck = model:FindFirstChild("Neck", true)
                if record.Neck and record.Neck:IsA("Motor6D") then record.NeckC0 = record.Neck.C0 else record.Neck = nil end
                -- Client scene actors use a grounded motion controller. Native
                -- Humanoid physics can fling imported, scaled avatar assemblies.
                record.Root.Anchored = true
                for _,part in ipairs(model:GetDescendants()) do
                    if part:IsA("BasePart") then part.CanCollide=false end
                end
                self.Records[record.Id], self.Pending[record] = record, nil
                if self.ApplyLoadout then pcall(self.ApplyLoadout,self,record) end
                table.insert(record.Connections, connect(model.Destroying,function() self:Remove(record) end))
                table.insert(record.Connections, connect(record.Humanoid.Died,function() self:Remove(record) end))
                self.Selected = record
            end, debug.traceback)
            if generation == self.Generation then self.PendingCount = math.max(0,self.PendingCount-1) end
            if not ok then self:Remove(record); if generation == self.Generation then self.LastError = tostring(err) end; changed(); return false,tostring(err) end
            self.LastError = nil; changed(); return true,record
        end
        function npc:SpawnGroup(count, avatar, name)
            if self.Batch then return false, "A group is already loading." end
            count = math.clamp(math.floor(tonumber(count) or 5),1,self.Limit)
            local token = {}; self.Batch = token
            local generation = self.Generation
            schedule(function()
                for _=1,count do
                    if generation ~= self.Generation or not alive() then break end
                    local ok = self:Spawn(avatar,name)
                    if not ok then break end
                    task.wait(.15)
                end
                if self.Batch == token then self.Batch = nil end
                changed()
            end)
            return true
        end
        local function makeBubble(record)
            local gui = Instance.new("BillboardGui")
            gui.Name, gui.Adornee, gui.Size = "NPCBubble", record.Head, UDim2.fromOffset(248,110)
            gui.StudsOffsetWorldSpace, gui.MaxDistance, gui.AlwaysOnTop = Vector3.new(0,2.4,0),65,false
            gui.LightInfluence, gui.Parent = 0,record.Model
            local body = Instance.new("Frame",gui)
            body.AnchorPoint, body.Position, body.Size = Vector2.new(.5,1),UDim2.fromScale(.5,.9),UDim2.fromOffset(58,32)
            body.BackgroundColor3, body.BorderSizePixel = Color3.fromRGB(248,248,250),0
            Instance.new("UICorner",body).CornerRadius = UDim.new(0,12)
            local tail = Instance.new("Frame",body)
            tail.Size,tail.Position,tail.AnchorPoint,tail.Rotation = UDim2.fromOffset(9,9),UDim2.new(.5,0,1,-1),Vector2.new(.5,.5),45
            tail.BackgroundColor3,tail.BorderSizePixel = body.BackgroundColor3,0
            local label = Instance.new("TextLabel",body)
            label.Size,label.Position = UDim2.new(1,-22,1,-12),UDim2.fromOffset(11,6)
            label.BackgroundTransparency,label.TextColor3 = 1,Color3.fromRGB(38,39,43)
            label.Font,label.TextSize,label.TextWrapped,label.RichText = Enum.Font.Gotham,14,true,false
            return {Gui=gui,Body=body,Tail=tail,Label=label}
        end
        function npc:Say(record, message, immediate, automatic)
            if type(record)=="number" then record=self.Records[record] end
            if not self.ChatEnabled or not record or record.Disposed or not self.Records[record.Id] then return false end
            local now=os.clock()
            if automatic and ((record.ManualChatUntil or 0)>now or (record.ChatNext or 0)>now
                or (record.Bubble and record.Bubble.Gui.Enabled and record.Bubble.EndAt>now)) then return false end
            message=clipped(message,140)
            if message=="" then return false end
            if not record.Bubble then record.Bubble=makeBubble(record) end
            local bubble=record.Bubble
            local length=utf8.len(message) or #message
            bubble.Message,bubble.Start = message,now
            bubble.ReadyAt = now + (immediate and 0 or math.clamp(length*rng:NextNumber(.035,.065), .65,3.2))
            bubble.EndAt = bubble.ReadyAt + math.clamp(3+length*.045,4,8)
            bubble.Gui.Enabled=true; bubble.Shown=false
            record.ChatNext=bubble.EndAt+rng:NextNumber(9,18)
            if not automatic then record.ManualChatUntil=bubble.EndAt+3 end
            -- A moving player can type without everybody coming to a full stop.
            if (record.ActualSpeed or 0)<2 or rng:NextNumber()<.35 then
                record.PauseUntil = bubble.ReadyAt + rng:NextNumber(.4,1)
            end
            return true
        end
        function npc:SetChat(enabled)
            self.ChatEnabled = enabled == true; self.Reply=nil
            table.clear(self.Replies)
            if not self.ChatEnabled then
                for _,r in pairs(self.Records) do if r.Bubble then r.Bubble.Gui.Enabled=false; r.Bubble.EndAt=0 end end
            end
            changed()
        end
        function npc:SetChatPace(pace)
            if pace~="Quiet" and pace~="Normal" and pace~="Lively" then return false end
            self.ChatPace=pace;self.ChatNext=os.clock()+rng:NextNumber(3,7);changed();return true
        end
        function npc:Emote(record,gesture)
            record = record or self.Selected
            gesture=gesture or "Wave"
            if not record or record.Disposed or not record.AnimationsEnabled or not record.Tracks[gesture]
                or (gesture~="Wave" and gesture~="Point" and gesture~="Cheer" and gesture~="Laugh") then return false end
            if record.Gesture and record.Tracks[record.Gesture] then record.Tracks[record.Gesture]:Stop(.15) end
            record.PauseUntil=os.clock()+2.3; record.MoveTarget=nil
            record.Gesture=gesture;record.GestureUntil=os.clock()+3
            record.Tracks[gesture]:Play(.2);return true
        end
        local function resetNavigation(record)
            record.Goal,record.MoveTarget,record.RequestedGoal=nil,nil,nil
            record.NavGeneration+=1;destroyPath(record)
            record.NextDecision=0;record.ForcePath=nil;record.Velocity=Vector3.zero;record.ActualSpeed=0
        end
        function npc:SetRecordMode(record,mode)
            if type(record)=="number" then record=self.Records[record] end
            if not record or record.Disposed or (mode~="Group" and mode~="Follow" and mode~="Roam" and mode~="Stay") then return false end
            record.ModeOverride=mode~="Group" and mode or nil
            record.Mode=record.ModeOverride or self.Mode;record.Home=record.Root.Position
            resetNavigation(record);changed();return true
        end
        function npc:SetRecordPaused(record,paused)
            if type(record)=="number" then record=self.Records[record] end
            if not record or record.Disposed then return false end
            record.Paused=paused==true;resetNavigation(record);changed();return true
        end
        function npc:SetAnimations(record,enabled)
            if type(record)=="number" then record=self.Records[record] end
            if not record or record.Disposed then return false end
            record.AnimationsEnabled=enabled==true;record.Animation=nil;record.Gesture=nil
            for _,track in pairs(record.Tracks) do track:Stop(.15) end
            if record.Neck and record.Neck.Parent then record.Neck.C0=record.NeckC0 end
            if record.Footsteps then record.Footsteps:Stop() end
            changed();return true
        end
        function npc:Jump(record)
            if not record or record.Disposed or record.Airborne or os.clock()<(record.NextJump or 0) then return false end
            -- Ground starts its ray five studs above the supplied position.
            if not self:Ground(record.Root.Position,record.Height+6) then return false end
            record.Airborne,record.VerticalVelocity=true,26
            record.NextJump=os.clock()+1.2;return true
        end
        function npc:SetMode(mode)
            if mode~="Follow" and mode~="Roam" and mode~="Stay" then return false end
            self.Mode=mode
            for _,r in pairs(self.Records) do
                r.Mode,r.Home=r.ModeOverride or mode,r.Root.Position;resetNavigation(r)
            end
            changed();return true
        end
        function npc:SetPaused(paused)
            self.Paused=paused==true
            for _,r in pairs(self.Records) do resetNavigation(r) end
            changed()
        end
        function npc:Recall()
            local root=playerRoot();if not root then return false end
            table.clear(self.History);table.clear(self.Replies)
            for _,r in pairs(self.Records) do
                local floor=self:SafePosition(root.Position,8+self:Count()*.5)
                if floor then
                    r.NavGeneration+=1;destroyPath(r);r.Goal=nil;r.MoveTarget=nil;r.Airborne=false;r.VerticalVelocity=0
                    r.Velocity=Vector3.zero;r.ActualSpeed=0;r.Recoveries=0;r.ForcePath=nil
                    r.Model:PivotTo(CFrame.new(floor+Vector3.new(0,r.Height+.2,0))*root.CFrame.Rotation)
                    r.Root.AssemblyLinearVelocity,r.Root.AssemblyAngularVelocity=Vector3.zero,Vector3.zero
                    r.Home,r.LastProgress,r.LastProgressAt=floor,floor,os.clock()
                    r.NextDecision=os.clock()+rng:NextNumber(.4,1.6)
                end
            end
            return true
        end
        function npc:Navigate(record, goal, forcePath)
            if not alive() or record.Disposed then return false end
            local now=os.clock()
            local delta=goal-record.Root.Position
            if flat(delta).Magnitude<record.Deadzone*.4 then record.Goal=nil;record.MoveTarget=nil;return true end
            record.RequestedGoal=goal
            local blocked=workspace:Raycast(record.Root.Position,delta,self:RayParams())
            local safe=true
            for fraction=.2,1,.2 do
                local sample=record.Root.Position:Lerp(goal,fraction)
                if not self:Ground(sample,record.Height+7) then safe=false;break end
            end
            if not forcePath and not blocked and safe then
                record.NavGeneration+=1;destroyPath(record);record.Goal=goal
                record.MoveTarget=goal;record.ForcePath=nil;return true
            end
            record.Goal=goal;record.ForcePath=true
            if record.PathPending then
                if record.ComputingGoal and (record.ComputingGoal-goal).Magnitude>8 then record.NavGeneration+=1 end
                return false
            end
            if now<record.NextPath or self.PathCount>=2 or now-self.LastPathStart<.16 then return false end
            record.NavGeneration+=1
            local token,generation=record.NavGeneration,self.Generation
            record.PathPending=true;record.NextPath=now+1.1;self.LastPathStart=now;self.PathCount+=1
            record.ComputingGoal=goal;record.ForcePath=nil
            schedule(function()
                local path
                local ok=pcall(function()
                    path=Pathfinding:CreatePath({AgentRadius=math.max(1.3,record.BodyRadius+.45),AgentHeight=math.max(4,record.Height+2),AgentCanJump=true,WaypointSpacing=3})
                    record.ComputingPath=path
                    path:ComputeAsync(record.Root.Position,goal)
                end)
                self.PathCount=math.max(0,self.PathCount-1);record.PathPending=false;record.ComputingPath=nil;record.ComputingGoal=nil
                if not alive() or record.Disposed or generation~=self.Generation or token~=record.NavGeneration then
                    if path then path:Destroy() end;return
                end
                if ok and path and path.Status==Enum.PathStatus.Success and #path:GetWaypoints()>1 then
                    destroyPath(record);record.Path=path;record.Waypoints=path:GetWaypoints();record.Waypoint=2;record.Goal=goal;record.JumpWaypoint=nil
                    record.PathFailures=0;record.ForcePath=nil
                    record.PathConnection=connect(path.Blocked,function(index)
                        if record.Path==path and index>=(record.Waypoint or 1) then
                            destroyPath(record);record.NextPath=0;record.NextDecision=0;record.ForcePath=true
                        end
                    end)
                else
                    if path then path:Destroy() end
                    record.PathFailures=(record.PathFailures or 0)+1
                    record.NextPath=os.clock()+math.min(4,1+record.PathFailures*.7)
                    record.ForcePath=true;record.MoveTarget=nil
                    if record.PathFailures>=3 then
                        record.Goal,record.RequestedGoal,record.ForcePath=nil,nil,nil
                        record.NextDecision=os.clock()+rng:NextNumber(2,4)
                    end
                end
            end)
            return true
        end
        local function chooseGaze(record,now,root)
            local partner=record.TalkPartner and npc.Records[record.TalkPartner]
            if partner and now<(record.TalkUntil or 0) and (partner.Root.Position-record.Root.Position).Magnitude<20 then
                record.LookAt=partner.Head.Position;return
            end
            if now<(record.NextGaze or 0) then return end
            record.NextGaze=now+rng:NextNumber(1.3,3.8)
            local nearby={}
            for _,other in pairs(npc.Records) do
                if other~=record and (other.Root.Position-record.Root.Position).Magnitude<14 then table.insert(nearby,other) end
            end
            if #nearby>0 and rng:NextNumber()<record.Profile.Social then
                record.LookAt=nearby[rng:NextInteger(1,#nearby)].Head.Position
            elseif root and (root.Position-record.Root.Position).Magnitude<18 and rng:NextNumber()<.6 then
                record.LookAt=root.Position+Vector3.new(0,1.5,0)
            else
                local angle=rng:NextNumber(-.65,.65)
                record.LookAt=record.Head.Position+record.Root.CFrame:VectorToWorldSpace(Vector3.new(math.sin(angle)*8,rng:NextNumber(-.6,.5),-8))
            end
        end
        local function animate(record,now,root,dt)
            local speed=record.ActualSpeed or 0
            if record.Footsteps then
                local audible=npc.FootstepsEnabled and record.AnimationsEnabled and speed>1 and not record.Airborne
                record.Footsteps.PlaybackSpeed=math.clamp(speed/13,.7,1.45)
                if audible and not record.Footsteps.IsPlaying then record.Footsteps:Play()
                elseif not audible and record.Footsteps.IsPlaying then record.Footsteps:Stop() end
            end
            if not record.AnimationsEnabled then return end
            local name=record.Airborne and ((record.VerticalVelocity or 0)>0 and "Jump" or "Fall") or (speed>.65 and "Walk" or "Idle")
            if name=="Idle" then
                if now>record.NextIdleStyle then
                    record.NextIdleStyle=now+rng:NextNumber(8,19);record.IdleVariant=record.IdleVariant=="Idle2" and "Idle" or "Idle2"
                end
                name=record.IdleVariant or "Idle"
            end
            if record.Animation~=name then
                for _,key in ipairs({"Idle","Idle2","Walk","Jump","Fall"}) do
                    local track=record.Tracks[key];if track and key~=name then track:Stop(.2) end
                end
                local track=record.Tracks[name]
                if track then
                    track:Play(.2,1,1)
                    if (name=="Idle" or name=="Idle2") and track.Length>0 then track.TimePosition=rng:NextNumber(0,track.Length*.75) end
                end
                record.Animation=name
            end
            if name=="Walk" and record.Tracks.Walk then record.Tracks.Walk:AdjustSpeed(math.clamp(speed/13,.35,1.65)) end
            if record.Gesture and now>(record.GestureUntil or 0) then record.Gesture=nil end
            chooseGaze(record,now,root)
            if record.Neck and record.Neck.Parent and record.LookAt then
                local relative=record.Root.CFrame:PointToObjectSpace(record.LookAt)
                local yaw=math.clamp(math.atan2(-relative.X,-relative.Z),-.55,.55)
                local pitch=math.clamp(math.atan2(relative.Y-record.Height*.55,math.max(1,flat(relative).Magnitude)),-.2,.2)
                record.Neck.C0=record.Neck.C0:Lerp(record.NeckC0*CFrame.Angles(pitch,yaw,0),1-math.exp(-7*(dt or 1/30)))
            end
        end
        local function updateBubble(record,now)
            local b=record.Bubble;if not b or not b.Gui.Enabled then return end
            if now>=b.EndAt then b.Gui.Enabled=false;return end
            if now<b.ReadyAt then
                b.Label.Text=string.rep(".",1+math.floor((now-b.Start)*4)%3);b.Body.Size=UDim2.fromOffset(54,32)
            elseif not b.Shown then
                b.Shown=true;b.Label.Text=b.Message
                local bounds=TextService:GetTextSize(b.Message,14,Enum.Font.Gotham,Vector2.new(208,100))
                b.Body.Size=UDim2.fromOffset(math.clamp(bounds.X+24,58,232),math.clamp(bounds.Y+18,34,96))
            end
            local fade=math.clamp((now-(b.EndAt-.5))/.5,0,1)
            b.Label.TextTransparency=fade;b.Body.BackgroundTransparency=fade;b.Tail.BackgroundTransparency=fade
        end
        function npc:Steer(record,direction)
            local current=record.Root.Position
            local avoidance=Vector3.zero
            for _,other in pairs(self.Records) do
                if other~=record and not other.Disposed and math.abs(other.Root.Position.Y-current.Y)<4 then
                    local otherPosition=self.Positions and self.Positions[other.Id] or other.Root.Position
                    local away=flat(current-otherPosition)
                    local distance=away.Magnitude
                    local personal=record.BodyRadius+other.BodyRadius+1
                    if distance<personal+1 then
                        local push=distance>.05 and away.Unit or Vector3.new(record.Id<other.Id and -1 or 1,0,0)
                        avoidance+=push*math.clamp((personal+1-distance)/(personal+1),0,1)*1.8
                    end
                    if distance<6 and direction:Dot(unit(-away))>.5 then
                        -- Opposing walkers consistently pass on their own right.
                        local otherDirection=unit(other.Velocity or Vector3.zero)
                        if otherDirection.Magnitude<.2 or direction:Dot(otherDirection)<-.2 then
                            avoidance+=Vector3.new(-direction.Z,0,direction.X)*(6-distance)*.22
                        end
                    end
                end
            end
            for _,position in ipairs(self.PlayerPositions or {}) do
                if math.abs(position.Y-current.Y)<4 then
                    local away=flat(current-position)
                    if away.Magnitude<4.5 then
                        avoidance+=unit(away)*math.max(0,3.5-away.Magnitude)*.45
                        if direction:Dot(unit(-away))>.6 then
                            avoidance+=Vector3.new(-direction.Z,0,direction.X)*(4.5-away.Magnitude)*.22
                        end
                    end
                end
            end
            if direction.Magnitude==0 then return Vector3.zero end
            -- A stopped character keeps its place. Steering applies only while walking.
            return unit(direction+avoidance)
        end
        function npc:Move(record,dt,freeze)
            local current=record.Root.Position
            local target=not freeze and record.MoveTarget or nil
            local horizontal=target and flat(target-current) or Vector3.zero
            local distance=horizontal.Magnitude
            local direction=distance>.35 and horizontal.Unit or Vector3.zero
            local steer=self:Steer(record,direction)
            local speed=record.Humanoid.WalkSpeed
            if not record.Waypoints or record.Waypoint==#record.Waypoints then
                speed=math.min(speed,math.sqrt(math.max(0,distance-.3)*48))
            end
            local requested=steer*speed
            local velocity=record.Velocity or Vector3.zero
            local change=requested-velocity
            local rate=(requested.Magnitude<velocity.Magnitude or requested:Dot(velocity)<0) and 40 or record.Profile.Acceleration
            velocity+=unit(change)*math.min(change.Magnitude,rate*dt)
            if freeze then velocity=Vector3.zero end
            local step=velocity*dt
            if direction.Magnitude>0 and step:Dot(direction)>distance then step=direction*distance end
            local params=self:RayParams()
            local body=Vector3.new(record.BodyRadius*1.7,math.max(2,record.Height*1.15),record.BodyRadius*1.7)
            local function traversable(delta)
                local floor=self:Ground(current+delta,record.Height+(record.Airborne and 16 or 9))
                if not floor or floor.Y+record.Height-current.Y>3.2 then return nil end
                local hit=delta.Magnitude>.001 and workspace:Blockcast(CFrame.new(current),body,delta,params) or nil
                if hit then return nil,hit end
                for _,other in pairs(self.Records) do
                    if other~=record and math.abs(other.Root.Position.Y-current.Y)<4 then
                        -- Steering uses a consistent snapshot, but the hard guard
                        -- must see actors already moved earlier in this update.
                        local relative=flat(current-other.Root.Position)
                        local before=relative.Magnitude
                        local fraction=delta.Magnitude>.001 and math.clamp(-relative:Dot(delta)/delta:Dot(delta),0,1) or 0
                        local closest=(relative+delta*fraction).Magnitude
                        -- No visual interpenetration; actors can always move out of an overlap.
                        if closest<math.min(record.BodyRadius+other.BodyRadius+.25,before)-.0001 then return nil end
                    end
                end
                for _,position in ipairs(self.PlayerPositions or {}) do
                    if math.abs(position.Y-current.Y)<4 then
                        local relative=flat(current-position)
                        local before=relative.Magnitude
                        local fraction=delta.Magnitude>.001 and math.clamp(-relative:Dot(delta)/delta:Dot(delta),0,1) or 0
                        local closest=(relative+delta*fraction).Magnitude
                        if closest<math.min(record.BodyRadius+1.2,before)-.0001 then return nil end
                    end
                end
                return floor
            end
            local floor,hit=traversable(step)
            if not floor and step.Magnitude>.001 then
                -- Slide a little along a wall before asking for a new path.
                local x,z=Vector3.new(step.X,0,0),Vector3.new(0,0,step.Z)
                if math.abs(step.X)>math.abs(step.Z) then z,x=x,z end
                local alternative=traversable(z)
                if alternative and z.Magnitude>.005 then floor,step=alternative,z
                else alternative=traversable(x);if alternative and x.Magnitude>.005 then floor,step=alternative,x end end
                if not floor then
                    record.ForcePath=true
                    if hit and direction.Magnitude>0 and not record.Airborne then
                        local ahead=current+direction*2.8
                        local low=workspace:Raycast(current-Vector3.new(0,record.Height-.5,0),direction*2.8,params)
                        local high=workspace:Raycast(current+Vector3.new(0,1.5,0),direction*2.8,params)
                        local landing=self:Ground(ahead,record.Height+8)
                        if low and not high and landing and landing.Y-current.Y+record.Height<3.2 then self:Jump(record) end
                    end
                    step,velocity=Vector3.zero,Vector3.zero
                end
            end
            floor=floor or self:Ground(current,record.Height+(record.Airborne and 16 or 9))
            local moved=current+step
            if floor then
                local floorY=floor.Y+record.Height
                if record.Airborne then
                    record.VerticalVelocity=(record.VerticalVelocity or 0)-75*dt
                    local y=current.Y+record.VerticalVelocity*dt
                    if y<=floorY and record.VerticalVelocity<=0 then y=floorY;record.Airborne=false;record.VerticalVelocity=0 end
                    if record.VerticalVelocity>0 then
                        local rise=Vector3.new(0,y-current.Y,0)
                        if rise.Y>0 and workspace:Blockcast(CFrame.new(current),body,rise,params) then record.VerticalVelocity=0;y=current.Y end
                    end
                    moved=Vector3.new(moved.X,y,moved.Z)
                else
                    moved=Vector3.new(moved.X,current.Y+math.clamp(floorY-current.Y,-22*dt,22*dt),moved.Z)
                end
            else
                -- A streamed-out or unsupported floor never lets a local actor fall.
                moved=current;velocity=Vector3.zero;record.ForcePath=true
            end
            record.Velocity=velocity
            local actual=flat(moved-current)
            record.ActualSpeed=actual.Magnitude/math.max(dt,.001)
            local rotation=record.Root.CFrame.Rotation
            if actual.Magnitude>.015 then
                rotation=rotation:Lerp(CFrame.lookAt(Vector3.zero,actual.Unit).Rotation,1-math.exp(-record.Profile.Turn*dt))
            end
            record.Root.CFrame=CFrame.new(moved)*rotation
            if distance<.55 then record.MoveTarget=nil end
        end
        function npc:FollowPosition(record,now,root)
            local sample=self.History[1]
            local at=now-record.Profile.Reaction
            for i=#self.History,1,-1 do
                if self.History[i].At<=at then sample=self.History[i];break end
            end
            local cf=sample and sample.CFrame or root.CFrame
            local right,forward=unit(flat(cf.RightVector)),unit(flat(cf.LookVector))
            local drift=math.sin(now*.16+record.Phase)*.65
            return cf.Position+right*(self.Spread*record.Side+drift)-forward*(self.Spread*record.Back)
        end
        function npc:Recover(record,now)
            record.Recoveries=(record.Recoveries or 0)+1
            record.LastProgressAt=now;record.LastProgress=record.Root.Position
            if record.Recoveries==1 then
                record.NextPath=0;record.ForcePath=true
                self:Navigate(record,record.Goal,true)
            elseif record.Recoveries==2 then
                local direction=unit(flat(record.Goal-record.Root.Position))
                local side=Vector3.new(-direction.Z,0,direction.X)*(record.Id%2==0 and 1 or -1)
                for _,sign in ipairs({1,-1}) do
                    local offset=side*sign*3.5-direction
                    local floor=self:Ground(record.Root.Position+offset,record.Height+6)
                    if floor and not workspace:Raycast(record.Root.Position,offset,self:RayParams()) then
                        destroyPath(record);record.MoveTarget=floor+Vector3.new(0,record.Height,0)
                        record.RecoveryUntil=now+1.1;record.NextDecision=now+1.1;return
                    end
                end
                record.NextPath=0;self:Navigate(record,record.Goal,true)
            else
                -- Give up an unreachable target instead of bouncing or teleporting.
                resetNavigation(record);record.Velocity=Vector3.zero
                record.NextDecision=now+rng:NextNumber(1.4,3);record.Recoveries=0
            end
        end
        function npc:UpdateChat(now,root)
            if not self.ChatEnabled or not root then return end
            for i=#self.Replies,1,-1 do
                local reply=self.Replies[i]
                if now>=reply.At then
                    table.remove(self.Replies,i)
                    local speaker=self.Records[reply.Speaker]
                    local record=self.Records[reply.Record]
                    if record and speaker and (record.Root.Position-speaker.Root.Position).Magnitude<20 then
                        if self:Say(record,reply.Text,false,true) then
                            record.TalkPartner,speaker.TalkPartner=speaker.Id,record.Id
                            record.TalkUntil,speaker.TalkUntil=now+7,now+7
                            if rng:NextNumber()<.16 and (record.ActualSpeed or 0)<1 then self:Emote(record,"Laugh") end
                        end
                    end
                end
            end
            if now<self.ChatNext then return end
            local intervals={Quiet={17,30},Normal={9,18},Lively={6,12}}
            local interval=intervals[self.ChatPace] or intervals.Normal
            self.ChatNext=now+rng:NextNumber(interval[1],interval[2])
            local nearby={}
            for _,record in pairs(self.Records) do
                if (record.Root.Position-root.Position).Magnitude<40 and now>=(record.ChatNext or 0)
                    and now>=(record.ManualChatUntil or 0) and not (record.Bubble and record.Bubble.Gui.Enabled) then table.insert(nearby,record) end
            end
            if #nearby==0 then return end
            local speaker=nearby[rng:NextInteger(1,#nearby)]
            local context=(speaker.ActualSpeed or 0)>2 and "Moving" or "Idle"
            local pool={}
            for index,dialog in ipairs(conversations) do
                if (dialog.Context==context or dialog.Context=="Any") and index~=self.LastDialog and index~=speaker.LastDialog then table.insert(pool,index) end
            end
            local index=pool[rng:NextInteger(1,#pool)];local dialog=conversations[index]
            if not self:Say(speaker,dialog[1],false,true) then return end
            self.LastDialog,speaker.LastDialog=index,index
            local partner
            local closest=19
            for _,other in ipairs(nearby) do
                local distance=(other.Root.Position-speaker.Root.Position).Magnitude
                if other~=speaker and distance<closest then partner,closest=other,distance end
            end
            if partner then
                local at=speaker.Bubble.ReadyAt+rng:NextNumber(1.2,2.8)
                table.insert(self.Replies,{Record=partner.Id,Speaker=speaker.Id,Text=dialog[2],At=at})
                speaker.TalkPartner,partner.TalkPartner=partner.Id,speaker.Id
                speaker.TalkUntil,partner.TalkUntil=at+8,at+8
                -- Reserve the listener so another automatic exchange cannot cut in.
                partner.ChatNext=at
            elseif (speaker.ActualSpeed or 0)<1 and rng:NextNumber()<.2 then self:Emote(speaker,"Wave") end
        end
        function npc:Step(now)
            if not alive() then return end
            local dt=math.clamp(now-(self.LastStep or now-1/30),.001,.1);self.LastStep=now
            local root=playerRoot()
            if root then
                if self.NeedsRecall or (self.LastRoot and (root.Position-self.LastRoot).Magnitude>65 and now>(self.NextRecall or 0)) then
                    self:Recall();self.NextRecall=now+4;self.NeedsRecall=false
                end
                self.LastRoot=root.Position
                table.insert(self.History,{At=now,CFrame=root.CFrame})
                while #self.History>75 or (#self.History>1 and self.History[1].At<now-2.5) do table.remove(self.History,1) end
            end
            self.Positions={}
            for id,record in pairs(self.Records) do self.Positions[id]=record.Root.Position end
            self.PlayerPositions=root and {root.Position} or {}
            for _,player in ipairs(Players:GetPlayers()) do
                local character=player.Character
                local otherRoot=character and character:FindFirstChild("HumanoidRootPart")
                if otherRoot and otherRoot~=root then table.insert(self.PlayerPositions,otherRoot.Position) end
            end
            for _,r in pairs(self.Records) do
                if not r.Model.Parent or r.Humanoid.Health<=0 then self:Remove(r);continue end
                updateBubble(r,now)
                if not root or self.Paused or r.Paused or (r.PauseUntil or 0)>now then
                    r.MoveTarget=nil;r.ActualSpeed=0;r.Goal=nil
                    if not r.MotionPaused then r.NavGeneration+=1;destroyPath(r);r.MotionPaused=true end
                    self:Move(r,dt,true);animate(r,now,root,dt);continue
                end
                if r.MotionPaused then r.MotionPaused=false;r.NextDecision=0 end
                if r.Root.Position.Y<workspace.FallenPartsDestroyHeight+30 or r.Root.Position.Y<root.Position.Y-65 then self:Recall();break end
                local position=r.Root.Position
                if flat(position-r.LastProgress).Magnitude>1.2 then r.LastProgress,r.LastProgressAt=position,now;r.Recoveries=0 end
                if r.Waypoints then
                    local point=r.Waypoints[r.Waypoint]
                    if point and Vector3.new(position.X-point.Position.X,0,position.Z-point.Position.Z).Magnitude<.8
                        and math.abs(position.Y-r.Height-point.Position.Y)<3 then
                        r.Waypoint+=1;point=r.Waypoints[r.Waypoint]
                    end
                    if point then
                        if point.Action==Enum.PathWaypointAction.Jump and not r.Airborne and r.JumpWaypoint~=r.Waypoint then
                            if self:Jump(r) then r.JumpWaypoint=r.Waypoint end
                        end
                        r.MoveTarget=point.Position
                    else destroyPath(r);r.Goal=nil;r.MoveTarget=nil end
                end
                self:Move(r,dt);animate(r,now,root,dt)
                if now<r.NextDecision then continue end
                r.NextDecision=now+r.Profile.Reaction+rng:NextNumber(.1,.3)
                if r.Mode=="Stay" then
                    r.MoveTarget=nil
                    if now>r.NextIdle then
                        r.NextIdle=now+rng:NextNumber(8,18)
                        if rng:NextNumber()<.2 then self:Emote(r) end
                    end
                    continue
                end
                local desired
                if r.Mode=="Roam" then
                    if now>r.NextIdle then desired=self:SafePosition(r.Home,12);r.NextIdle=now+rng:NextNumber(4,9) end
                else
                    local humanoid=root.Parent and root.Parent:FindFirstChildOfClass("Humanoid")
                    local moving=flat(root.AssemblyLinearVelocity).Magnitude>1 or (humanoid and humanoid.MoveDirection.Magnitude>.05)
                    local target=self:FollowPosition(r,now,root)
                    local separation=flat(target-position).Magnitude
                    if (moving and separation>r.Deadzone) or (root.Position-position).Magnitude>self.Spread*1.7+4 then
                        desired=self:Ground(target,18)
                        r.Humanoid.WalkSpeed=r.Speed+((root.Position-position).Magnitude>24 and 4 or 0)
                    elseif moving and separation<=r.Deadzone then
                        r.MoveTarget=nil;r.Goal=nil
                    elseif now>r.NextIdle then
                        r.NextIdle=now+rng:NextNumber(5,11)
                        r.Humanoid.WalkSpeed=r.Speed
                        if rng:NextNumber()<.22 then self:Emote(r)
                        elseif rng:NextNumber()<.65 then desired=self:SafePosition(position,4.5) end
                    end
                end
                if desired then
                    local goal=desired+Vector3.new(0,r.Height,0)
                    if not r.Goal or (goal-r.Goal).Magnitude>3 or r.ForcePath then self:Navigate(r,goal,r.ForcePath) end
                end
                if r.ForcePath and r.Goal and not r.PathPending then self:Navigate(r,r.Goal,true) end
                if r.Goal and flat(r.Goal-position).Magnitude>3 and not r.PathPending and now-r.LastProgressAt>2.5 then
                    self:Recover(r,now)
                end
            end
            self:UpdateChat(now,root)
        end
        -- A caller-supplied leader owns its own lifecycle. The actual player's
        -- respawn must not move actors attached to a different scene/leader.
        if not options.GetRoot then
            connect(localPlayer.CharacterAdded,function(character)
                if not character:WaitForChild("HumanoidRootPart",10) or character~=localPlayer.Character or not alive() then return end
                for _,r in pairs(npc.Records) do npc:BindPlayerCollisions(r) end
                npc.LastRoot=nil;npc.NeedsRecall=true
            end)
        end
        if not options.Manual then
            schedule(function()
                while alive() do
                    local ok,err=pcall(function() npc:Step(os.clock()) end)
                    if not ok then npc.LastError=tostring(err);changed();task.wait(1) end
                    task.wait(1/30)
                end
            end)
        end
        Runtime.cleanup(function() npc:Shutdown() end)
        return npc
    end
    Runtime.NPC = Runtime.createNPCController()
end
-- END NPC RUNTIME

local tradeModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("TradeModule"))
local inventoryModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("InventoryModule"))
local itemModule = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ItemModule"))
local profileData = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ProfileData"))
local sync = require(ReplicatedStorage:WaitForChild("Database"):WaitForChild("Sync"))
local itemPopupService = require(ReplicatedStorage:WaitForChild("ClientServices"):WaitForChild("ItemPopupService"))

function Runtime.tradeReady()
    local gui = tradeModule.GUI
    local trade = gui and gui.TradeGUI
    if typeof(trade) ~= "Instance" or not trade.Parent then return false, "Trade UI is not initialized." end
    local container = trade:FindFirstChild("Container")
    local items = container and container:FindFirstChild("Items")
    -- ItemsLayout is an optional override (used by some device layouts).
    -- Desktop leaves it nil; InventoryModule supplies its default grid.
    if not items or not items:FindFirstChild("Main") then
        return false, "Trade inventory layout is unavailable."
    end
    for _, name in ipairs({"YourOffer", "TheirOffer", "Actions"}) do
        if typeof(gui[name]) ~= "Instance" or not gui[name].Parent then return false, "Trade " .. name .. " is unavailable." end
    end
    if not gui.YourOffer:FindFirstChild("Container") or not gui.TheirOffer:FindFirstChild("Container")
        or not gui.TheirOffer:FindFirstChild("Username") then return false, "Trade offer layout is unavailable." end
    return true
end
function Runtime.tradeOpen()
    return Runtime.Active and _G.CartiHubFakeTradeActive == true
        and Runtime.tradeReady() and tradeModule.GUI.TradeGUI.Enabled == true
end
function Runtime.resetTradePending()
    _G.CartiHubAutoTradeSearchPending = nil
    _G.CartiHubAutoUpgradeOfferPending = nil
    _G.CartiHubPendingFakeTradeUsername = nil
    _G.CartiHubActiveFakeTradeUsername = nil
    _G.CartiHubInstantFakeTradeReturnPending = false
    Runtime.TradeStarting = false
end

-- These entries reference Decal assets in the game database. Inventory cards
-- need the underlying texture thumbnail rather than the Decal asset itself.
for _, itemContainer in ipairs({ sync.Weapons, sync.Item }) do
    if itemContainer then
        if itemContainer.IcecreamChroma then
            itemContainer.IcecreamChroma.Image = "rbxthumb://type=Asset&w=150&h=150&id=90300177211738"
        end

        if itemContainer.BeachyChroma then
            itemContainer.BeachyChroma.Image = "rbxthumb://type=Asset&w=150&h=150&id=134952503728391"
        end

        if itemContainer.SandsChroma then
            itemContainer.SandsChroma.Image = "rbxthumb://type=Asset&w=150&h=150&id=104927341820800"
        end
    end
end

local currentWeaponAmount = 1
local MAX_WEAPON_AMOUNT = 113
local BUTTON_COLOR = Color3.fromRGB(31, 11, 52)
local BUTTON_HOVER_COLOR = Color3.fromRGB(59, 25, 91)
local SakaUI

-- Block credentials are entered at runtime and are not stored in this file.
local function safeParent()
    return localPlayer:WaitForChild("PlayerGui")
end

local function getProfileOwnedTable(itemType)
    if itemType == "Weapons" or itemType == "Item" then
        return profileData.Weapons and profileData.Weapons.Owned
    elseif itemType == "Pets" then
        return profileData.Pets and profileData.Pets.Owned
    end

    local bucket = profileData[itemType]
    return bucket and bucket.Owned
end

-- Never write fake counts into the server-supplied profile. Generate inventory
-- frames from a copy, combining ownership with this run's display-only overlay.
_G.CartiHubFakeInventoryAmounts = _G.CartiHubFakeInventoryAmounts or {}
Runtime.Inventory = { Deltas = {} }
-- Older versions wrote fake totals into Owned. Re-read the official local
-- profile once on upgrade; a fake total cannot reveal the original real count.
Runtime.Inventory.NeedsLegacyRefresh = _G.CartiHubInventoryOverlayVersion ~= 2
    and next(_G.CartiHubFakeInventoryAmounts) ~= nil
function Runtime.Inventory.amount(value)
    value = tonumber(value) or 0
    if value ~= value or value == math.huge or value == -math.huge then return 0 end
    return math.floor(value)
end

function CartiHubGetFakeInventoryKey(itemId, itemType)
    local bucket = itemType == "Item" and "Weapons" or tostring(itemType)
    return bucket .. ":" .. tostring(itemId)
end

function CartiHubGetFakeInventoryAmount(itemId, itemType)
    return tonumber(_G.CartiHubFakeInventoryAmounts[CartiHubGetFakeInventoryKey(itemId, itemType)]) or 0
end

function CartiHubSetFakeInventoryAmount(itemId, itemType, amount)
    local key = CartiHubGetFakeInventoryKey(itemId, itemType)
    amount = math.max(0, Runtime.Inventory.amount(amount))
    _G.CartiHubFakeInventoryAmounts[key] = amount > 0 and amount or nil
    return amount
end

function CartiHubAddFakeInventoryAmount(itemId, itemType, delta)
    return CartiHubSetFakeInventoryAmount(
        itemId,
        itemType,
        CartiHubGetFakeInventoryAmount(itemId, itemType) + (tonumber(delta) or 0)
    )
end

function Runtime.Inventory.visibleAmount(itemId, itemType)
    local owned = getProfileOwnedTable(itemType)
    local key = CartiHubGetFakeInventoryKey(itemId, itemType)
    return math.max(0, Runtime.Inventory.amount(owned and owned[itemId])
        + CartiHubGetFakeInventoryAmount(itemId, itemType)
        + (Runtime.Inventory.Deltas[key] or 0))
end
function Runtime.Inventory.view(source, fake, deltas)
    local result = table.clone(source)
    for itemType, bucket in pairs(source) do
        if type(bucket) == "table" and type(bucket.Owned) == "table" then
            result[itemType] = table.clone(bucket)
            result[itemType].Owned = table.clone(bucket.Owned)
        end
    end
    local keys = {}
    for key in pairs(fake) do keys[key] = true end
    for key in pairs(deltas) do keys[key] = true end
    for key in pairs(keys) do
        local itemType, itemId = key:match("^([^:]+):(.+)$")
        local bucket = itemType and result[itemType]
        if bucket and type(bucket.Owned) == "table" then
            local amount = math.max(0, Runtime.Inventory.amount(bucket.Owned[itemId])
                + Runtime.Inventory.amount(fake[key]) + Runtime.Inventory.amount(deltas[key]))
            bucket.Owned[itemId] = amount > 0 and amount or nil
        end
    end
    -- MM2's Item database aliases weapon ownership.
    if result.Item and result.Weapons then result.Item = result.Weapons end
    return result
end
function Runtime.Inventory.profile()
    if not Runtime.Active then return profileData end
    return Runtime.Inventory.view(profileData, _G.CartiHubFakeInventoryAmounts, Runtime.Inventory.Deltas)
end

local function clearMainInventoryContainers()
    local gui = inventoryModule.GUI and inventoryModule.GUI.MyInventory
    if not gui or not gui.Main then
        return false
    end

    local blank = inventoryModule.CreateBlankInventoryTable()

    for itemType, categories in pairs(blank) do
        local typeFrame = gui.Main:FindFirstChild(itemType)
        local itemsContainer = typeFrame
            and typeFrame:FindFirstChild("Items")
            and typeFrame.Items:FindFirstChild("Container")

        if itemsContainer then
            for categoryName in pairs(categories) do
                local categoryFrame = itemsContainer:FindFirstChild(categoryName)

                if not categoryFrame and itemsContainer:FindFirstChild("Holiday") then
                    local holiday = itemsContainer.Holiday:FindFirstChild("Container")
                    categoryFrame = holiday and holiday:FindFirstChild(categoryName)
                end

                local container = categoryFrame and categoryFrame:FindFirstChild("Container")
                if container then
                    container:ClearAllChildren()
                end
            end
        end
    end

    return true
end

local function refreshMainInventoryNow()
    local gui = inventoryModule.GUI and inventoryModule.GUI.MyInventory
    if not gui or not gui.Main then
        return false
    end

    if not clearMainInventoryContainers() then
        return false
    end

    local ok, newInventory = pcall(function()
        return inventoryModule.GenerateInventory(gui, Runtime.Inventory.profile())
    end)

    if not ok then
        warn("[Carti Hub] Main inventory refresh failed: " .. tostring(newInventory))
        return false
    end

    inventoryModule.MyInventory = newInventory

    pcall(function()
        inventoryModule.ConnectEquipButtons()
    end)

    pcall(function()
        inventoryModule.UpdateMyEquip()
    end)

    return true
end

Runtime.Inventory.refresh = refreshMainInventoryNow
if Runtime.Inventory.NeedsLegacyRefresh then
    task.spawn(function()
        local original = profileData.Weapons and profileData.Weapons.Owned
        local snapshot = type(original) == "table" and table.clone(original) or {}
        local ok, authoritative = pcall(function()
            return ReplicatedStorage.Remotes.Inventory.GetProfileData:InvokeServer()
        end)
        if not Runtime.Active then return end
        local unchanged = profileData.Weapons and profileData.Weapons.Owned == original
        if unchanged then
            for id, amount in pairs(original) do if snapshot[id] ~= amount then unchanged = false; break end end
            for id, amount in pairs(snapshot) do if original[id] ~= amount then unchanged = false; break end end
        end
        if ok and unchanged and type(authoritative) == "table" and type(authoritative.Weapons) == "table"
            and type(authoritative.Weapons.Owned) == "table" then
            profileData.Weapons.Owned = table.clone(authoritative.Weapons.Owned)
            _G.CartiHubInventoryOverlayVersion = 2
            Runtime.Inventory.NeedsLegacyRefresh = false
            refreshMainInventoryNow()
        else
            warn("[Carti Hub] Previous fake counts could not be reconciled; rejoin once to refresh real ownership.")
        end
    end)
else
    _G.CartiHubInventoryOverlayVersion = 2
end
task.spawn(function()
    local lastSignature, lastInventory
    while Runtime.Active do
        local parts = {}
        for itemType, bucket in pairs(Runtime.Inventory.profile()) do
            if type(bucket) == "table" and type(bucket.Owned) == "table" then
                for id, amount in pairs(bucket.Owned) do
                    table.insert(parts, tostring(itemType) .. ":" .. tostring(id) .. "=" .. tostring(amount))
                end
            end
        end
        table.sort(parts)
        local signature = table.concat(parts, "|")
        if signature ~= lastSignature or inventoryModule.MyInventory ~= lastInventory then
            if refreshMainInventoryNow() then
                lastSignature, lastInventory = signature, inventoryModule.MyInventory
            end
        end
        task.wait(0.5)
    end
end)

-- Fill this table manually. Prefer exact database ids as keys because display names can overlap.
-- The watcher below applies the matching visual whenever your local equipped knife/gun changes.
local WeaponVisuals = {
    ["Flowerwood Gun"] = {
        Type = "Gun",
        MeshId = "rbxassetid://16895099893",
        TextureId = "rbxassetid://16895448237",
        Scale = Vector3.new(0.05, 0.05, 0.05),
        Offset = Vector3.new(0, 0, 0),
        Placement = "WaistRight",
    },

    ["Lightbringer"] = {
        Type = "Gun",
        MeshId = "rbxassetid://4730813852",
        TextureId = "http://www.roblox.com/asset/?id=4728487789",
        Scale = Vector3.new(0.05, 0.05, 0.05),
        Offset = Vector3.new(0, 0, 0),
        Placement = "WaistRight",
    },

    ["Snowcannon"] = {
        Type = "Gun",
        MeshId = "rbxassetid://99836890880541",
        TextureId = "http://www.roblox.com/asset/?id=122392330922281",
        Scale = Vector3.new(0.05, 0.05, 0.05),
        Offset = Vector3.new(0, 0, 0),
        Placement = "WaistRight",
    },

    ["Gingerscythe"] = {
        Type = "Knife",
        MeshId = "rbxassetid://15395668244",
        TextureId = "http://www.roblox.com/asset/?id=15409195246",
        Scale = Vector3.new(0.06, 0.06, 0.06),
        Offset = Vector3.new(0, 0, 0),
        Placement = "Back",
    },

    ["Luger"] = {
        Type = "Gun",
        MeshId = "rbxassetid://95356090",
        TextureId = "http://www.roblox.com/asset/?id=126534866",
        Scale = Vector3.new(1.7999999523162842, 1.7999999523162842, 1.7999999523162842),
        Offset = Vector3.new(0, 0, 0),
        Placement = "WaistRight",
    },

    ["Darkbringer"] = {
        Type = "Gun",
        MeshId = "rbxassetid://4730813852",
        TextureId = "http://www.roblox.com/asset/?id=4728494788",
        Scale = Vector3.new(0.05, 0.05, 0.05),
        Offset = Vector3.new(0, 0, 0),
        Placement = "WaistRight",
    },

    ["Eternalcane"] = {
        Type = "Knife",
        MeshId = "rbxassetid://3132923779",
        TextureId = "http://www.roblox.com/asset/?id=4488374804",
        Scale = Vector3.new(0.949999988079071, 0.949999988079071, 0.949999988079071),
        Offset = Vector3.new(0, 0, 0),
        Placement = "WaistLeft",
    },

    ["Gingermint"] = {
        Type = "Gun",
        MeshId = "rbxassetid://11866444071",
        TextureId = "rbxassetid://11866444253",
        Scale = Vector3.new(0.05000000074505806, 0.05000000074505806, 0.05000000074505806),
        Offset = Vector3.new(0, 0, 0),
        Placement = "WaistRight",
    },
	["Elderwood Scythe"] = {
    Type = "Knife",
    MeshId = "rbxassetid://4217523241",
    TextureId = "http://www.roblox.com/asset/?id=4210044808",
    Scale = Vector3.new(0.07000000029802322, 0.07000000029802322, 0.07000000029802322),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.6392157077789307, 0.6352941393852234, 0.6470588445663452),
    Material = Enum.Material.Plastic,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    Chroma = false,
	Placement = "WaistLeft",
},
["Batwing"] = {
    Type = "Knife",
    MeshId = "http://www.roblox.com/asset/?id=305826272",
    TextureId = "rbxassetid://2511673515",
    Scale = Vector3.new(1, 1, 1),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.6392157077789307, 0.6352941393852234, 0.6470588445663452),
    Material = Enum.Material.Plastic,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    Chroma = false,
    AttachmentPosition = Vector3.new(0, 0, 0),
    AttachmentOrientation = Vector3.new(-0, 0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(0, 1, 0),
},
["Heartblade"] = {
    Type = "Knife",
    MeshId = "rbxassetid://6404140078",
    TextureId = "http://www.roblox.com/asset/?id=6413074818",
    Scale = Vector3.new(1, 1, 1),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.06666667014360428, 0.06666667014360428, 0.06666667014360428),
    Material = Enum.Material.Brick,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    Chroma = false,
	Placement = "WaistLeft",
},
["Candleflame"] = {
    Type = "Knife",
    MeshId = "rbxassetid://7791364860",
    TextureId = "rbxassetid://7791364988",
    Scale = Vector3.new(0.05999999865889549, 0.05999999865889549, 0.05999999865889549),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.06666667014360428, 0.06666667014360428, 0.06666667014360428),
    Material = Enum.Material.Brick,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    Chroma = false,
	Placement = "WaistLeft",
},
["Makeshift"] = {
    Type = "Gun",
    MeshId = "rbxassetid://11158364935",
    TextureId = "http://www.roblox.com/asset/?id=11274360089",
    Scale = Vector3.new(0.05000000074505806, 0.05000000074505806, 0.05000000074505806),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.6392157077789307, 0.6352941393852234, 0.6470588445663452),
    Material = Enum.Material.Plastic,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    Chroma = false,
},
["Plasmablade"] = {
    Type = "Knife",
    MeshId = "rbxassetid://9702732853",
    TextureId = "rbxassetid://10015130416",
    Scale = Vector3.new(0.0020000000949949026, 0.0020000000949949026, 0.0020000000949949026),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.06666667014360428, 0.06666667014360428, 0.06666667014360428),
    Material = Enum.Material.Brick,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    Chroma = false,
    AttachmentPosition = Vector3.new(0, 0, 0),
    AttachmentOrientation = Vector3.new(-0, 0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(0, 1, 0),
},
["Plasmabeam"] = {
    Type = "Gun",
    MeshId = "rbxassetid://9702755186",
    TextureId = "rbxassetid://10015208201",
    Scale = Vector3.new(0.05000000074505806, 0.05000000074505806, 0.05000000074505806),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.06666667014360428, 0.06666667014360428, 0.06666667014360428),
    Material = Enum.Material.Brick,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    Chroma = false,
    AttachmentPosition = Vector3.new(0.06429433822631836, 0.05646803602576256, 0.19186615943908691),
    AttachmentOrientation = Vector3.new(-73.00315856933594, -0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(-0, 0.2923188805580139, -0.9563208818435669),
},
["Harvester"] = {
    Type = "Gun",
    Placement = "WaistRight",
    MeshId = "rbxassetid://7775027413",
    TextureId = "http://www.roblox.com/asset/?id=7775245551",
    Scale = Vector3.new(0.05999999865889549, 0.05999999865889549, 0.05999999865889549),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.06666667014360428, 0.06666667014360428, 0.06666667014360428),
    Material = Enum.Material.Brick,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    Chroma = false,
    AttachmentPosition = Vector3.new(0.1299028992652893, 0.000002229222218375071, 0.07500199228525162),
    AttachmentOrientation = Vector3.new(-0.0026997302193194628, -60, 90.00231170654297),
    AttachmentAxis = Vector3.new(0.000020563602447509766, 1, -0.00005862116813659668),
    AttachmentSecondaryAxis = Vector3.new(-0.5, -0.00004048561822855845, -0.8660253882408142),
},
["Bat"] = {
    Type = "Knife",
    MeshId = "rbxassetid://11182796403",
    TextureId = "rbxassetid://11192090515",
    Scale = Vector3.new(0.07000000029802322, 0.07000000029802322, 0.07000000029802322),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.6392157077789307, 0.6352941393852234, 0.6470588445663452),
    Material = Enum.Material.Plastic,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    Chroma = false,
    AttachmentPosition = Vector3.new(0, 0, 0),
    AttachmentOrientation = Vector3.new(-0, 0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(0, 1, 0),
},
["ChromaLightbringer"] = {
    Type = "Gun",
    MeshId = "rbxassetid://4730813852",
    TextureId = "http://www.roblox.com/asset/?id=4728487789",
    Scale = Vector3.new(0.039000000804662704, 0.039000000804662704, 0.039000000804662704),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.6392157077789307, 0.6352941393852234, 0.6470588445663452),
    Material = Enum.Material.Plastic,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    AttachmentPosition = Vector3.new(5.4977863522831256e-15, -0.1866021752357483, 0.12320592254400253),
    AttachmentOrientation = Vector3.new(-80.00140380859375, -0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(-0, 0.17362435162067413, -0.9848120212554932),
    Chroma = true,
    ChromaTexture = "rbxassetid://4751498862",
    ChromaStaticLayer = "rbxassetid://18364488166",
},
["ChromaCandleflame"] = {
    Type = "Knife",
    MeshId = "rbxassetid://7791364860",
    TextureId = "rbxassetid://7791364988",
    Scale = Vector3.new(0.039000000804662704, 0.039000000804662704, 0.039000000804662704),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.6392157077789307, 0.6352941393852234, 0.6470588445663452),
    Material = Enum.Material.Plastic,
    Transparency = 0,
	Placement = "WaistLeft",
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    AttachmentPosition = Vector3.new(5.4977863522831256e-15, -0.1866021752357483, 0.12320592254400253),
    AttachmentOrientation = Vector3.new(-80.00140380859375, -0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(-0, 0.17362435162067413, -0.9848120212554932),
    Chroma = true,
    ChromaTexture = "rbxassetid://4751498862",
    ChromaStaticLayer = "rbxassetid://18364488166",
},
["Vampire's Gun"] = {
    Type = "Gun",
    MeshId = "rbxassetid://126591885289479",
    TextureId = "rbxassetid://104946799389637",
    Scale = Vector3.new(0.05000000074505806, 0.05000000074505806, 0.05000000074505806),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.6392157077789307, 0.6352941393852234, 0.6470588445663452),
    Material = Enum.Material.Slate,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    AttachmentPosition = Vector3.new(0, -0.20000000298023224, 0.08990859985351562),
    AttachmentOrientation = Vector3.new(-50.001827239990234, -0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(-0, 0.6427633166313171, -0.7660649418830872),
    Chroma = false,
    ChromaTexture = "",
    ChromaStaticLayer = "",
},
["Raygun"] = {
    Type = "Gun",
    MeshId = "rbxassetid://115447220952926",
    TextureId = "rbxassetid://127881437685243",
    Scale = Vector3.new(0.05000000074505806, 0.05000000074505806, 0.05000000074505806),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.6392157077789307, 0.6352941393852234, 0.6470588445663452),
    Material = Enum.Material.Slate,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    AttachmentPosition = Vector3.new(0, -0.20000000298023224, 0.08990859985351562),
    AttachmentOrientation = Vector3.new(-50.001827239990234, -0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(-0, 0.6427633166313171, -0.7660649418830872),
    Chroma = false,
    ChromaTexture = "",
    ChromaStaticLayer = "",
},
["Nightblade"] = {
    Type = "Knife",
    MeshId = "http://www.roblox.com/asset/?id=103838505",
    TextureId = "http://www.roblox.com/asset/?id=103838996",
    Scale = Vector3.new(0.699999988079071, 0.44999998807907104, 0.5),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.38823530077934265, 0.37254902720451355, 0.3843137323856354),
    Material = Enum.Material.Plastic,
    Transparency = 0,
	Placement = "WaistLeft",
    Reflectance = 0,
    VertexColor = Vector3.new(0.4000000059604645, 0.4000000059604645, 0.4000000059604645),
    AttachmentPosition = Vector3.new(0.006067206151783466, 0.15098965167999268, 0.04653354361653328),
    AttachmentOrientation = Vector3.new(4.996701717376709, -0.15615952014923096, -0.17513397336006165),
    AttachmentAxis = Vector3.new(0.999992311000824, -0.0030450436752289534, 0.002459252253174782),
    AttachmentSecondaryAxis = Vector3.new(0.00281926360912621, 0.9961950778961182, 0.08710600435733795),
    Chroma = false,
    ChromaTexture = "",
    ChromaStaticLayer = "",
},
["Icebreaker"] = {
    Type = "Knife",
    MeshId = "rbxassetid://6124173614",
    TextureId = "rbxassetid://6124173821",
    Scale = Vector3.new(1, 1, 1),
	Placement = "WaistLeft",
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.06666667014360428, 0.06666667014360428, 0.06666667014360428),
    Material = Enum.Material.Brick,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    AttachmentPosition = Vector3.new(0, 0, 0),
    AttachmentOrientation = Vector3.new(-0, 0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(0, 1, 0),
    Chroma = false,
    ChromaTexture = "",
    ChromaStaticLayer = "",
},
["Hallow's Edge"] = {
    Type = "Knife",
    MeshId = "http://www.roblox.com/asset?id=179155055",
    TextureId = "http://www.roblox.com/asset?id=179155105",
    Scale = Vector3.new(0.550000011920929, 0.550000011920929, 0.5550000071525574),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.6392157077789307, 0.6352941393852234, 0.6470588445663452),
    Material = Enum.Material.Plastic,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    AttachmentPosition = Vector3.new(0, 0, 0),
    AttachmentOrientation = Vector3.new(-0, 0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(0, 1, 0),
    Chroma = false,
    ChromaTexture = "",
    ChromaStaticLayer = "",
},
["Eternal IV"] = {
    Type = "Knife",
    MeshId = "rbxassetid://3132923779",
    TextureId = "http://www.roblox.com/asset/?id=4999951444",
    Scale = Vector3.new(0.949999988079071, 0.949999988079071, 0.949999988079071),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.6392157077789307, 0.6352941393852234, 0.6470588445663452),
    Material = Enum.Material.Plastic,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    AttachmentPosition = Vector3.new(0, 0, 0),
    AttachmentOrientation = Vector3.new(-0, 0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(0, 1, 0),
    Chroma = false,
    ChromaTexture = "",
    ChromaStaticLayer = "",
},
["Icewing"] = {
    Type = "Knife",
    Placement = "WaistLeft",
    MeshId = "rbxassetid://3183449780",
    TextureId = "rbxassetid://2279588369",
    Scale = Vector3.new(0.08500000089406967, 0.08500000089406967, 0.08500000089406967),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.6392157077789307, 0.6352941393852234, 0.6470588445663452),
    Material = Enum.Material.Plastic,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    AttachmentPosition = Vector3.new(0.00309753674082458, -0.009521819651126862, 0.20591194927692413),
    AttachmentOrientation = Vector3.new(-19.19320297241211, 179.1589813232422, 1.235748291015625),
    AttachmentAxis = Vector3.new(-0.9997638463973999, 0.02036745660007, -0.007585207931697369),
    AttachmentSecondaryAxis = Vector3.new(0.01673959381878376, 0.9441957473754883, 0.32895931601524353),
    Chroma = false,
    ChromaTexture = "",
    ChromaStaticLayer = "",
},
["Peppermint"] = {
    Type = "Knife",
    MeshId = "rbxassetid://6085025295",
    TextureId = "http://www.roblox.com/asset/?id=6074789360",
    Scale = Vector3.new(0.05999999865889549, 0.05999999865889549, 0.05999999865889549),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.06666667014360428, 0.06666667014360428, 0.06666667014360428),
    Material = Enum.Material.Brick,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    AttachmentPosition = Vector3.new(0, 0, 0),
    AttachmentOrientation = Vector3.new(-0, 0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(0, 1, 0),
    Chroma = false,
    ChromaTexture = "",
    ChromaStaticLayer = "",
},
["Rainbow"] = {
    Type = "Knife",
    MeshId = "rbxassetid://12921240966",
    TextureId = "rbxassetid://12921241867",
    Scale = Vector3.new(0.05999999865889549, 0.05999999865889549, 0.05999999865889549),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.06666667014360428, 0.06666667014360428, 0.06666667014360428),
    Material = Enum.Material.Brick,
    Transparency = 0,
	Placement = "WaistLeft",
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    AttachmentPosition = Vector3.new(0, 0, 0),
    AttachmentOrientation = Vector3.new(-0, 0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(0, 1, 0),
    Chroma = false,
    ChromaTexture = "",
    ChromaStaticLayer = "",
},
["Spirit"] = {
    Type = "Knife",
    MeshId = "rbxassetid://112444333460928",
    TextureId = "rbxassetid://131787177447081",
    Scale = Vector3.new(0.07999999821186066, 0.07999999821186066, 0.07999999821186066),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.6392157077789307, 0.6352941393852234, 0.6470588445663452),
    Material = Enum.Material.Slate,
    Transparency = 0,
    Reflectance = 0,
	Placement = "WaistLeft",
    VertexColor = Vector3.new(1, 1, 1),
    AttachmentPosition = Vector3.new(0, 0, 0),
    AttachmentOrientation = Vector3.new(-0, 0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(0, 1, 0),
    Chroma = false,
    ChromaTexture = "",
    ChromaStaticLayer = "",
},
["SeerChroma"] = {
    Type = "Knife",
    MeshId = "http://www.roblox.com/asset?id=156092238",
    TextureId = "rbxassetid://3184059718",
    Scale = Vector3.new(0.699999988079071, 0.9100000262260437, 1),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.6392157077789307, 0.6352941393852234, 0.6470588445663452),
    Material = Enum.Material.Plastic,
    Transparency = 0.20000000298023224,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    AttachmentPosition = Vector3.new(0, 0, 0),
    AttachmentOrientation = Vector3.new(-0, 0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(0, 1, 0),
    Chroma = true,
    ChromaTexture = "rbxassetid://3184061374",
    ChromaStaticLayer = "rbxassetid://18364485783",
},
["Swirly Gun"] = {
    Type = "Gun",
    MeshId = "rbxassetid://8310911339",
    TextureId = "rbxassetid://8293539377",
    Scale = Vector3.new(0.8999999761581421, 0.8999999761581421, 0.8999999761581421),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.06666667014360428, 0.06666667014360428, 0.06666667014360428),
    Material = Enum.Material.Brick,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    AttachmentPosition = Vector3.new(0, 0, 0),
    AttachmentOrientation = Vector3.new(-0, 0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(0, 1, 0),
    Chroma = false,
    ChromaTexture = "",
    ChromaStaticLayer = "",
},
["Fang"] = {
    Type = "Knife",
    MeshId = "http://www.roblox.com/asset/?id=117500241",
    TextureId = "http://www.roblox.com/asset/?id=117500388",
    Scale = Vector3.new(0.4000000059604645, 0.3700000047683716, 0.3700000047683716),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.38823530077934265, 0.37254902720451355, 0.3843137323856354),
    Material = Enum.Material.Concrete,
    Transparency = 0,
    Reflectance = 0,
		Placement = "WaistLeft",
    VertexColor = Vector3.new(1, 1, 1),
    AttachmentPosition = Vector3.new(-9.536782954455703e-07, -9.536768175166799e-07, -9.536794323139475e-07),
    AttachmentOrientation = Vector3.new(0.06901711970567703, -92.26690673828125, 1.0130547285079956),
    AttachmentAxis = Vector3.new(-0.039569735527038574, 0.017680207267403603, 0.9990603923797607),
    AttachmentSecondaryAxis = Vector3.new(-0.0005041101248934865, 0.9998430609703064, -0.01771402359008789),
    Chroma = false,
    ChromaTexture = "",
    ChromaStaticLayer = "",
},
["Cookieblade"] = {
    Type = "Knife",
    MeshId = "rbxassetid://6123168377",
    TextureId = "rbxassetid://6123168583",
    Scale = Vector3.new(1.2999999523162842, 1.2999999523162842, 1.2999999523162842),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.06666667014360428, 0.06666667014360428, 0.06666667014360428),
    Material = Enum.Material.Brick,
    Transparency = 0.20000000298023224,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    AttachmentPosition = Vector3.new(0, 0, 0),
    AttachmentOrientation = Vector3.new(-0, 0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(0, 1, 0),
    Chroma = false,
    ChromaTexture = "",
    ChromaStaticLayer = "",
},
["Slasher"] = {
    Type = "Knife",
    MeshId = "http://www.roblox.com/asset/?id=283709822",
    TextureId = "http://www.roblox.com/asset/?id=313894904",
    Scale = Vector3.new(0.6000000238418579, 0.6000000238418579, 0.6000000238418579),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.6392157077789307, 0.6352941393852234, 0.6470588445663452),
    Material = Enum.Material.Plastic,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    AttachmentPosition = Vector3.new(0, 0, 0),
    AttachmentOrientation = Vector3.new(-0, 0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(0, 1, 0),
    Chroma = false,
    ChromaTexture = "",
    ChromaStaticLayer = "",
},
["Icepiercer"] = {
    Type = "Gun",
    Placement = "WaistRight",
    MeshId = "rbxassetid://11868991644",
    TextureId = "rbxassetid://11869075814",
    Scale = Vector3.new(0.05999999865889549, 0.05999999865889549, 0.05999999865889549),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.6392157077789307, 0.6352941393852234, 0.6470588445663452),
    Material = Enum.Material.Plastic,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    AttachmentPosition = Vector3.new(0.1299028992652893, 0.000002229222218375071, 0.07500199228525162),
    AttachmentOrientation = Vector3.new(-0.0026997302193194628, -60, 90.00231170654297),
    AttachmentAxis = Vector3.new(0.000020563602447509766, 1, -0.00005862116813659668),
    AttachmentSecondaryAxis = Vector3.new(-0.5, -0.00004048561822855845, -0.8660253882408142),
    Chroma = false,
    ChromaTexture = "",
    ChromaStaticLayer = "",
},
["Purple Seer"] = {
    Type = "Knife",
    MeshId = "http://www.roblox.com/asset?id=156092238",
    TextureId = "rbxassetid://3184063317",
    Scale = Vector3.new(0.699999988079071, 0.9100000262260437, 1),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.6392157077789307, 0.6352941393852234, 0.6470588445663452),
    Material = Enum.Material.Plastic,
    Transparency = 0,
    Reflectance = 0,
	Placement = "WaistLeft",
    VertexColor = Vector3.new(1, 1, 1),
    AttachmentPosition = Vector3.new(0, 0, 0),
    AttachmentOrientation = Vector3.new(-0, 0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(0, 1, 0),
    Chroma = false,
    ChromaTexture = "",
    ChromaStaticLayer = "",
},
["Snowstorm"] = {
    Type = "Knife",
    MeshId = "rbxassetid://86944837615327",
    TextureId = "rbxassetid://84853425379784",
    Scale = Vector3.new(0.07000000029802322, 0.07000000029802322, 0.07000000029802322),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.6392157077789307, 0.6352941393852234, 0.6470588445663452),
    Material = Enum.Material.Slate,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    AttachmentPosition = Vector3.new(0, 0, 0),
    AttachmentOrientation = Vector3.new(-0, 0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(0, 1, 0),
    Chroma = false,
    ChromaTexture = "",
    ChromaStaticLayer = "",
},
["Blizzard"] = {
    Type = "Gun",
    MeshId = "rbxassetid://77235373292363",
    TextureId = "rbxassetid://131115493735176",
    Scale = Vector3.new(0.05000000074505806, 0.05000000074505806, 0.05000000074505806),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.6392157077789307, 0.6352941393852234, 0.6470588445663452),
    Material = Enum.Material.Plastic,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    AttachmentPosition = Vector3.new(0, -0.20000000298023224, 0.08990859985351562),
    AttachmentOrientation = Vector3.new(-50.001827239990234, -0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(-0, 0.6427633166313171, -0.7660649418830872),
    Chroma = false,
    ChromaTexture = "",
    ChromaStaticLayer = "",
},
["Iceblaster"] = {
    Type = "Gun",
    MeshId = "rbxassetid://6125828567",
    TextureId = "rbxassetid://6120563948",
    Scale = Vector3.new(1, 1, 1),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.06666667014360428, 0.06666667014360428, 0.06666667014360428),
    Material = Enum.Material.Brick,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    AttachmentPosition = Vector3.new(0, 1, 0),
    AttachmentOrientation = Vector3.new(-0, 0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(0, 1, 0),
    Chroma = false,
    ChromaTexture = "",
    ChromaStaticLayer = "",
},
["Ice Shard"] = {
    Type = "Knife",
    MeshId = "http://www.roblox.com/asset/?id=188539751 ",
    TextureId = "http://www.roblox.com/asset/?id=188539820 ",
    Scale = Vector3.new(1.2000000476837158, 1.2000000476837158, 1.2000000476837158),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.6392157077789307, 0.6352941393852234, 0.6470588445663452),
    Material = Enum.Material.Plastic,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    AttachmentPosition = Vector3.new(-0.0099992910400033, -0.13704271614551544, -0.17640718817710876),
    AttachmentOrientation = Vector3.new(-85.05686950683594, -175.63331604003906, 179.4180908203125),
    AttachmentAxis = Vector3.new(0.9978162050247192, 0.0008751153945922852, -0.06604611873626709),
    AttachmentSecondaryAxis = Vector3.new(-0.06572528928518295, -0.08616232872009277, -0.9941107630729675),
    Chroma = false,
    ChromaTexture = "",
    ChromaStaticLayer = "",
},
["Candy"] = {
    Type = "Knife",
    MeshId = "http://www.roblox.com/asset/?id=19040337",
    TextureId = "http://www.roblox.com/asset/?id=19040326",
    Scale = Vector3.new(1.100000023841858, 1.399999976158142, 1.100000023841858),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.8039215803146362, 0.8039215803146362, 0.8039215803146362),
    Material = Enum.Material.Plastic,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    AttachmentPosition = Vector3.new(0, 0, 0),
    AttachmentOrientation = Vector3.new(-0, 0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(0, 1, 0),
    Chroma = false,
    ChromaTexture = "",
    ChromaStaticLayer = "",
},
["Waves"] = {
    Type = "Knife",
    MeshId = "rbxassetid://13916938702",
    TextureId = "rbxassetid://13916939964",
    Scale = Vector3.new(0.09000000357627869, 0.09000000357627869, 0.09000000357627869),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.06666667014360428, 0.06666667014360428, 0.06666667014360428),
    Material = Enum.Material.Brick,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    AttachmentPosition = Vector3.new(0, 0, 0),
    AttachmentOrientation = Vector3.new(-0, 0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(0, 1, 0),
    Chroma = false,
    ChromaTexture = "",
    ChromaStaticLayer = "",
},
["Logchopper"] = {
    Type = "Knife",
    MeshId = "rbxassetid://4535643726",
    TextureId = "rbxassetid://4535641077",
    Scale = Vector3.new(1, 1, 1),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.06666667014360428, 0.06666667014360428, 0.06666667014360428),
    Material = Enum.Material.Brick,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    AttachmentPosition = Vector3.new(0, 0, 0),
    AttachmentOrientation = Vector3.new(-0, 0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(0, 1, 0),
    Chroma = false,
	Placement = "WaistLeft",
    ChromaTexture = "",
    ChromaStaticLayer = "",
},
["Turkey"] = {
    Type = "Knife",
    MeshId = "rbxassetid://15320557481",
    TextureId = "rbxassetid://15320558272",
    Scale = Vector3.new(0.0560000017285347, 0.0560000017285347, 0.0560000017285347),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.6392157077789307, 0.6352941393852234, 0.6470588445663452),
    Material = Enum.Material.Plastic,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    AttachmentPosition = Vector3.new(0, 0, 0),
    AttachmentOrientation = Vector3.new(-0, 0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(0, 1, 0),
    Chroma = false,
    ChromaTexture = "",
    ChromaStaticLayer = "",
},
["Evergun"] = {
    Type = "Gun",
    MeshId = "rbxassetid://15408863676",
    TextureId = "rbxassetid://15408849730",
    Scale = Vector3.new(0.019999999552965164, 0.019999999552965164, 0.019999999552965164),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.6392157077789307, 0.6352941393852234, 0.6470588445663452),
    Material = Enum.Material.Plastic,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    SurfaceColorMap = "",
    SurfaceMetalnessMap = "",
    SurfaceNormalMap = "",
    SurfaceRoughnessMap = "",
    SurfaceAlphaMode = Enum.AlphaMode.Overlay,
    AttachmentPosition = Vector3.new(0, -0.20000000298023224, 0.08990859985351562),
    AttachmentOrientation = Vector3.new(-50.001827239990234, -0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(-0, 0.6427633166313171, -0.7660649418830872),
    Chroma = false,
    ChromaTexture = "",
    ChromaStaticLayer = "",
    ChromaFace = Enum.NormalId.Back,
    CloneVisualChildrenFromPlayer = "caribbeansseas",
},
["Celestial"] = {
    Type = "Knife",
    MeshId = "rbxassetid://109711282082830",
    TextureId = "rbxassetid://79010754957272",
    Scale = Vector3.new(0.07, 0.07, 0.07),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.6392157077789307, 0.6352941393852234, 0.6470588445663452),
    Material = Enum.Material.Plastic,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    SurfaceColorMap = "rbxassetid://120904608273443",
    SurfaceMetalnessMap = "rbxassetid://95735363537147",
    SurfaceNormalMap = "",
    SurfaceRoughnessMap = "rbxassetid://115560145086368",
    SurfaceAlphaMode = Enum.AlphaMode.Overlay,
    UseSurfaceAppearance = false,
    Placement = "Back",
    AttachmentPosition = Vector3.new(0, 0, 0),
    AttachmentOrientation = Vector3.new(-0, 0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(0, 1, 0),
    Chroma = false,
    ChromaTexture = "",
    ChromaStaticLayer = "",
    ChromaFace = Enum.NormalId.Back,
},
["Bauble"] = {
    Type = "Gun",
    MeshId = "rbxassetid://107813118898769",
    TextureId = "rbxassetid://137012201908941",
    Scale = Vector3.new(0.05000000074505806, 0.05000000074505806, 0.05000000074505806),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.6392157077789307, 0.6352941393852234, 0.6470588445663452),
    Material = Enum.Material.Plastic,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    SurfaceColorMap = "",
    SurfaceMetalnessMap = "",
    SurfaceNormalMap = "",
    SurfaceRoughnessMap = "",
    SurfaceAlphaMode = Enum.AlphaMode.Overlay,
    UseSurfaceAppearance = false,
    Placement = "WaistRight",
    AttachmentPosition = Vector3.new(0, 0, 0),
    AttachmentOrientation = Vector3.new(-0, 0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(0, 1, 0),
    Chroma = false,
    ChromaTexture = "",
    ChromaStaticLayer = "",
    ChromaFace = Enum.NormalId.Back,
},
["Heart Wand"] = {
    Type = "Knife",
    MeshId = "rbxassetid://77738838473091",
    TextureId = "rbxassetid://76246633927299",
    Scale = Vector3.new(0.07, 0.07, 0.07),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.5607843399047852, 0.13333334028720856, 0.13333334028720856),
    Material = Enum.Material.Brick,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    SurfaceColorMap = "rbxassetid://76246633927299",
    SurfaceMetalnessMap = "",
	    Placement = "WaistLeft",
    SurfaceNormalMap = "",
    SurfaceRoughnessMap = "",
    SurfaceAlphaMode = Enum.AlphaMode.Overlay,
    AttachmentPosition = Vector3.new(0, 0, 0),
    AttachmentOrientation = Vector3.new(-0, 0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(0, 1, 0),
    Chroma = false,
    ChromaTexture = "",
    ChromaStaticLayer = "",
    ChromaFace = Enum.NormalId.Back,
},
["Sunrise"] = {
    Type = "Gun",
    MeshId = "rbxassetid://109742397574153",
    TextureId = "rbxassetid://71731808219690",
    Scale = Vector3.new(0.04584595561027527, 0.04584595561027527, 0.04584595561027527),
    Offset = Vector3.new(0, 0, 0),
    Color = Color3.new(0.6392157077789307, 0.6352941393852234, 0.6470588445663452),
    Material = Enum.Material.Plastic,
    Transparency = 0,
    Reflectance = 0,
    VertexColor = Vector3.new(1, 1, 1),
    SurfaceColorMap = "",
    SurfaceMetalnessMap = "",
    SurfaceNormalMap = "",
    SurfaceRoughnessMap = "",
    SurfaceAlphaMode = Enum.AlphaMode.Overlay,
    AttachmentPosition = Vector3.new(0, -0.20000000298023224, 0.08990859985351562),
    AttachmentOrientation = Vector3.new(-50.001827239990234, -0, 0),
    AttachmentAxis = Vector3.new(1, 0, 0),
    AttachmentSecondaryAxis = Vector3.new(-0, 0.6427633166313171, -0.7660649418830872),
    Chroma = true,
    ChromaTexture = "rbxassetid://122480499480858",
    ChromaStaticLayer = "",
    ChromaFace = Enum.NormalId.Left,
},
}

-- Evergreen uses the catalog loader so its light meshes have real geometry.

-- BEGIN CARTI VISUAL RENDERER
Runtime.Visual = {
    Entries = {}, States = {}, Models = {}, Loading = {}, RetryAt = {}, Status = {},
    SourceOverrides = {}, Selection = {}, Builds = {},
}
-- BEGIN VERIFIED WEAPON CATALOG
-- Asset identifiers and visual properties from vetted public data and exact-ID live captures.
-- Parsed as data, checked against the live database; no upstream scripts included.
-- See asset-research/ASSET_REPORT.md for provenance and validation limits.
Runtime.Visual.Catalog = {
    ["AmericaSword"] = {["ModelId"]="473570051",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.25,0.6,3.05),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=262027449",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.6,0.6,0.6),["TextureId"]="https://www.roblox.com/asset/?id=445805934",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Part",["Name"]="EffectFull",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,0,1,0,-1,0),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.25,3,0.65),["Transparency"]=1},["Children"]={}},{["Class"]="Part",["Name"]="EffectHalf",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0.60001,1,0,0,0,0,1,0,-1,0),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.25,1.8,0.65),["Transparency"]=1},["Children"]={}},{["Class"]="Part",["Name"]="EffectCenter",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0.07498,0.39996,1,0,0,0,0,1,0,-1,0),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.25,0.2,0.4),["Transparency"]=1},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0.01773,0.08072,-0.12479,0.99918,0.00772,0.03986,-0.04038,0.08672,0.99542,0.00423,-0.9962,0.08696)},["Children"]={}}}}},
    ["Amerilaser"] = {["ModelId"]="446050753",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.11666666376921876,0.6708332927690628,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(0.7,0.7,0.7),["HeldGripSize"]=Vector3.new(0.6,1,1.8),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.6,1,1.8),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=116657254",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.7,0.7,0.7),["TextureId"]="https://www.roblox.com/asset/?id=445884341",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["AuroraGun"] = {["ModelId"]="108635848059846",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.046926531097719736,0.046934514322992976,0.046925999999999995),["HeldGripSize"]=Vector3.new(0.45911,1.35493,2.3463),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="MeshPart",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(143,34,34),["DoubleSided"]=false,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://16070198638",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.45911,1.35493,2.3463),["TextureID"]="rbxassetid://107873598804292",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["AuroraKnife"] = {["ModelId"]="101343256002049",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(143,34,34),["DoubleSided"]=false,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://16025287191",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.22988,3.76599,1.15339),["TextureID"]="rbxassetid://97521579968070",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["BattleAxe"] = {["ModelId"]="1133237368",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,3,0.8),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://1084767698",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.56,0.56,0.56),["TextureId"]="rbxassetid://1084767901",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["BattleAxe2"] = {["ModelId"]="2513535503",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["DoubleSided"]=false,["Material"]=Enum.Material.Plastic,["MeshId"]="rbxassetid://2397016406",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.37879,3.6555,1.67011),["TextureID"]="rbxassetid://2513526862",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Bauble"] = {["ModelId"]="84481559639371",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.0471,0.0471,0.0471),["HeldGripSize"]=Vector3.new(0.48417,1.37511,2.08516),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.48417,1.37511,2.08516),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://107813118898769",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.0471,0.0471,0.0471),["TextureId"]="rbxassetid://137012201908941",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.23862,0.10727,1,0,0,0,0.64276,0.76607,0,-0.76607,0.64276)},["Children"]={}}}}},
    ["BaubleChroma"] = {["ModelId"]="84481559639371",["Type"]="Gun",["Chroma"]=true,["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.0471,0.0471,0.0471),["HeldGripSize"]=Vector3.new(0.48417,1.37511,2.08516),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.48417,1.37511,2.08516),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://107813118898769",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.0471,0.0471,0.0471),["TextureId"]="rbxassetid://137012201908941",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,0,0),["Face"]=Enum.NormalId.Left,["Texture"]="rbxassetid://129391884956433",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.23862,0.10727,1,0,0,0,0.64276,0.76607,0,-0.76607,0.64276)},["Children"]={}}}}},
    ["BaubleKnife"] = {["ModelId"]="111092946728824",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["DoubleSided"]=false,["Material"]=Enum.Material.Plastic,["MeshId"]="rbxassetid://116508096109443",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.49288,3.65592,0.83005),["TextureID"]="rbxassetid://135843404105980",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["BaubleKnifeChroma"] = {["ModelId"]="111092946728824",["Type"]="Knife",["Chroma"]=true,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.46874,3.47609,0.78916),["Transparency"]=0},["Children"]={{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,10,0),["Face"]=Enum.NormalId.Left,["Texture"]="rbxassetid://101916509598198",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://116508096109443",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.07326,0.07326,0.07326),["TextureId"]="rbxassetid://135843404105980",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Beachy"] = {["ModelId"]="120888453565511",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["Reflectance"]=0,["Color"]=Color3.fromRGB(163,162,165),["MeshId"]="rbxassetid://88652423673547",["RelCF"]=CFrame.new(0,0,0,1.0000003576278687,4.284083843231201e-8,0,4.284083843231201e-8,1.000000238418579,-7.450580596923828e-8,0,-7.450580596923828e-8,1.0000003576278687),["Transparency"]=0,["TextureID"]="",["Material"]=Enum.Material.Plastic,["CastShadow"]=true,["Size"]=Vector3.new(0.3693559169769287,3.5047643184661865,1.259381890296936)},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}},{["Class"]="SurfaceAppearance",["Name"]="SurfaceAppearance",["Props"]={["MetalnessMap"]="",["NormalMap"]="",["RoughnessMap"]="",["AlphaMode"]=Enum.AlphaMode.Overlay,["ColorMap"]="rbxassetid://128146857850145"},["Children"]={}}}}},
    ["BeachyChroma"] = {["ModelId"]="120888453565511",["Type"]="Knife",["Chroma"]=true,["Placement"]="WaistLeft",["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["Size"]=Vector3.new(0.71876,2.041385,3.095477),["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Color"]=Color3.fromRGB(163.00000350000002,161.99999549999998,164.99999400000002),["Material"]=Enum.Material.Plastic,["Shape"]=Enum.PartType.Block,["Reflectance"]=0,["Transparency"]=0,["CastShadow"]=true},["Children"]={{["Class"]="SpecialMesh",["Name"]="ChromaScanV2Mesh",["Props"]={["MeshType"]=Enum.MeshType.FileMesh,["MeshId"]="rbxassetid://88652423673547",["TextureId"]="rbxassetid://73559105239250",["Scale"]=Vector3.new(0.069919,0.069919,0.069919),["Offset"]=Vector3.new(0,0,0),["VertexColor"]=Vector3.new(1,1,1)},["Attributes"]={["CartiHubChromaMesh"]=true},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.354261,0.159256,1,0,0,0,0.642763,0.766065,0,-0.766065,0.642763)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Texture"]="rbxassetid://73559105239250",["Transparency"]=0,["Face"]=Enum.NormalId.Front,["Color3"]=Color3.fromRGB(255,255,255)},["Children"]={}}}}},
    ["Bioblade"] = {["ModelId"]="4751539262",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["DoubleSided"]=false,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://4662600017",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.31064,3.42103,1.08776),["TextureID"]="http://www.roblox.com/asset/?id=4751538400",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Blaster"] = {["ModelId"]="386277381",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.07499999813735493,0.6249999751647324,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(0.4,0.45,0.5),["HeldGripSize"]=Vector3.new(0.8,2,3.1),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(0,143,156),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.8,2,3.1),["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0.15,0.05489,0.2049,1,0,0,0,0.17362,0.98481,0,-0.98481,0.17362)},["Children"]={}},{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=92656610",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.4,0.45,0.5),["TextureId"]="https://www.roblox.com/asset/?id=386269992",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}}}}},
    ["BlizzardChroma"] = {["ModelId"]="88928894807422",["Type"]="Gun",["Chroma"]=true,["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.04334,0.04334,0.04334),["HeldGripSize"]=Vector3.new(0.4211,1.43482,2.0708),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4211,1.43482,2.0708),["Transparency"]=0},["Children"]={{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,19,0),["Face"]=Enum.NormalId.Left,["Texture"]="rbxassetid://110354859513948",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://77235373292363",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.04334,0.04334,0.04334),["TextureId"]="rbxassetid://97280881789656",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.19272,0.08664,1,0,0,0,0.64276,0.76607,0,-0.76607,0.64276)},["Children"]={}}}}},
    ["Bloom"] = {["ModelId"]="128553215441980",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(143,34,34),["DoubleSided"]=true,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://73266355643345",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.46137,3.7,1.03854),["TextureID"]="rbxassetid://103489229144925",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Blossom_G"] = {["ModelId"]="12339377105",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.31280793586645206,0.7682833857952468,1,-3.874311573781597e-7,9.83475501925568e-7,3.8742990682294476e-7,1,0.0000012665974509218358,-9.83475956672919e-7,-0.0000012665971098613227,1),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(0.04763,0.04413,0.04382),["HeldGripSize"]=Vector3.new(0.60612,0.26582,1.16242),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.60612,0.26582,1.16242),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://12322809632",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.04763,0.04413,0.04382),["TextureId"]="rbxassetid://12322809917",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.20001,0.0899,1,0,0,0,0.64276,0.76607,0,-0.76607,0.64276)},["Children"]={}}}}},
    ["BlueSeer"] = {["ModelId"]="3184125087",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.5,3.1,1),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset?id=156092238",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.7,0.91,1),["TextureId"]="rbxassetid://3184062977",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Boneblade"] = {["ModelId"]="2513505477",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,3,0.7),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://1857106669",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.7,0.7,0.7),["TextureId"]="rbxassetid://2516324337",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["BonebladeChroma"] = {["ModelId"]="2513598419",["Type"]="Knife",["Chroma"]=true,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,3,0.7),["Transparency"]=0},["Children"]={{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,9,0),["Face"]=Enum.NormalId.Front,["Texture"]="rbxassetid://2513578115",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://1857106669",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.73,0.73,0.73),["TextureId"]="rbxassetid://2513576265",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Candleflame"] = {["ModelId"]="7805833970",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["DoubleSided"]=false,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://7791364860",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.44978,3.33759,1.10873),["TextureID"]="rbxassetid://7791364988",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["CandleflameChroma"] = {["ModelId"]="7806121918",["Type"]="Knife",["Chroma"]=true,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,3,0.8),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://7791364860",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.06,0.06,0.06),["TextureId"]="rbxassetid://7806078587",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,9,0),["Face"]=Enum.NormalId.Front,["Texture"]="rbxassetid://7806088865",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Candy"] = {["ModelId"]="332021011",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(205,205,205),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,3,0.6),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=19040337",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(1.1,1.4,1.1),["TextureId"]="http://www.roblox.com/asset/?id=19040326",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Celestial"] = {["ModelId"]="136673966529736",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["DoubleSided"]=false,["Material"]=Enum.Material.Plastic,["MeshId"]="rbxassetid://109711282082830",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.39762,2.66487,2.364),["TextureID"]="rbxassetid://79010754957272",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Chill"] = {["ModelId"]="332022166",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.DiamondPlate,["Reflectance"]=0.01,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,3,0.8),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=105329941",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.5,0.5,0.5),["TextureId"]="http://www.roblox.com/asset/?id=105978218",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["ChromaDarkbringer"] = {["ModelId"]="4751501078",["Type"]="Gun",["Chroma"]=true,["HeldGrip"]=CFrame.new(0.02948054025446046,-0.37930106955212756,0.46498870651641616,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(0.03639,0.035,0.035),["HeldGripSize"]=Vector3.new(0.42663,1.37,1.65),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(0,143,156),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.42663,1.37,1.65),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://4730813852",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.03639,0.035,0.035),["TextureId"]="rbxassetid://4728494788",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,10,0),["Face"]=Enum.NormalId.Back,["Texture"]="rbxassetid://5278766434",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.18665,0.12321,1,0,0,0,0.17362,0.98481,0,-0.98481,0.17362)},["Children"]={}}}}},
    ["ChromaLightbringer"] = {["ModelId"]="4751500761",["Type"]="Gun",["Chroma"]=true,["HeldGrip"]=CFrame.new(0.02948054025446046,-0.37930106955212756,0.46498870651641616,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(0.03639,0.035,0.035),["HeldGripSize"]=Vector3.new(0.42663,1.37,1.65),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(0,143,156),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.42663,1.37,1.65),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://4730813852",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.03639,0.035,0.035),["TextureId"]="rbxassetid://5278764604",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,10,0),["Face"]=Enum.NormalId.Back,["Texture"]="rbxassetid://5278766434",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.18661,0.12323,1,0,0,0,0.17362,0.98481,0,-0.98481,0.17362)},["Children"]={}}}}},
    ["Clockwork"] = {["ModelId"]="473570519",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,0.65,3),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=352571495",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(1.1,1.6,1.2),["TextureId"]="http://www.roblox.com/asset/?id=352570357",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0.00151,-0.12701,-0.15448,-0.99867,0.03727,0.03568,-0.04098,-0.15276,-0.98741,-0.03135,-0.98756,0.15409)},["Children"]={}}}}},
    ["Constellation"] = {["ModelId"]="114197436469014",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.10066326301777069,0.10066229282358304,0.1006623332327568),["HeldGripSize"]=Vector3.new(0.53716,1.58302,2.36713),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="MeshPart",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["DoubleSided"]=false,["Material"]=Enum.Material.Plastic,["MeshId"]="rbxassetid://124598402927958",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.53716,1.58302,2.36713),["TextureID"]="rbxassetid://79010754957272",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.20001,0.08991,1,0,0,0,0.64276,0.76607,0,-0.76607,0.64276)},["Children"]={}}}}},
    ["ConstellationChroma"] = {["ModelId"]="114197436469014",["Type"]="Gun",["Chroma"]=true,["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.10123,0.10123,0.10123),["HeldGripSize"]=Vector3.new(0.537,1.583,2.367),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.537,1.583,2.367),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://124598402927958",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.10123,0.10123,0.10123),["TextureId"]="rbxassetid://123603327635244",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,9,0),["Face"]=Enum.NormalId.Left,["Texture"]="rbxassetid://97672028439457",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.51294,0.23058,1,0,0,0,0.64276,0.76607,0,-0.76607,0.64276)},["Children"]={}}}}},
    ["Cookieblade"] = {["ModelId"]="6125733703",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["DoubleSided"]=false,["Material"]=Enum.Material.Plastic,["MeshId"]="rbxassetid://6123168377",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.233,2.64,0.89999),["TextureID"]="rbxassetid://6123168583",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Darkbringer"] = {["ModelId"]="4749071819",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0.03111699783385068,-0.37930106955212756,0.46498870651641616,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(0.03841,0.035,0.035),["HeldGripSize"]=Vector3.new(0.45,1.26,1.7),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(0,143,156),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.45,1.26,1.7),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://4730813852",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.03841,0.035,0.035),["TextureId"]="rbxassetid://4728494788",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.18661,0.12323,1,0,0,0,0.17362,0.98481,0,-0.98481,0.17362)},["Children"]={}}}}},
    ["Darkshot"] = {["ModelId"]="15080280688",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(2.682209014892578e-7,-0.4587898254394531,0.6163902282714844,1,1.0279497786314096e-7,-5.81144320221938e-7,-1.0279489970344002e-7,1,1.3969771828215016e-7,5.81144320221938e-7,-1.396976614387313e-7,1),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(0.04000000283122063,0.04000000283122063,0.04000000283122063),["HeldGripSize"]=Vector3.new(0.3999999761581421,0.7999999523162842,2),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="Handle",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Transparency"]=0,["Reflectance"]=0,["Shape"]=Enum.PartType.Block,["Color"]=Color3.fromRGB(17.00000088661909,17.00000088661909,17.00000088661909),["Material"]=Enum.Material.Plastic,["CastShadow"]=true,["Size"]=Vector3.new(0.3999999761581421,0.7999999523162842,2)},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["Offset"]=Vector3.new(0,0,0),["VertexColor"]=Vector3.new(1,1,1),["MeshType"]=Enum.MeshType.FileMesh,["Scale"]=Vector3.new(0.04000000283122063,0.04000000283122063,0.04000000283122063),["MeshId"]="rbxassetid://15027451531",["TextureId"]="rbxassetid://15027451643"},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.20001,0.08994,1,0,0,0,0.64276,0.76607,0,-0.76607,0.64276)},["Children"]={}}}}},
    ["Darksword"] = {["ModelId"]="15080267070",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,3,0.7),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://15020899066",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.08,0.08,0.08),["TextureId"]="rbxassetid://15020899218",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Deathshard"] = {["ModelId"]="196750305",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(99,95,98),["Material"]=Enum.Material.Concrete,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.55,2.39,0.2),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=62275962 ",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.75,0.75,0.75),["TextureId"]="http://www.roblox.com/asset/?id=192567360",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,-0.0446,-0.00031,-0.99901,0.03549,0.99937,-0.00189,0.99837,-0.03553,-0.04456)},["Children"]={}}}}},
    ["DeathshardChroma"] = {["ModelId"]="3187390667",["Type"]="Knife",["Chroma"]=true,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(99,95,98),["Material"]=Enum.Material.Concrete,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.55,2.39,0.2),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://62275962",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.8,0.8,0.8),["TextureId"]="rbxassetid://3167029738",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,18,0),["Face"]=Enum.NormalId.Front,["Texture"]="rbxassetid://3167033529",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,0.00003,0,-0.0446,-0.00031,-0.999,0.03549,0.99937,-0.00189,0.99837,-0.03553,-0.04456)},["Children"]={}}}}},
    ["Eggblade"] = {["ModelId"]="6607277825",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["DoubleSided"]=false,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://6596834762",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.72136,3.43189,0.91195),["TextureID"]="http://www.roblox.com/asset/?id=6596824396",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["ElderwoodGun"] = {["ModelId"]="4211142894",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(-0.35,-0.3,0,0,0,-1,0,1,0,1,0,0),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.0298,0.029799871802029813,0.029800105834668945),["HeldGripSize"]=Vector3.new(1.49,1.13204,0.3587),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="MeshPart",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["DoubleSided"]=false,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://4210029922",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(1.49,1.13204,0.3587),["TextureID"]="http://www.roblox.com/asset/?id=4210038158",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(-0.22989,0.09821,0.1,0.00001,0.98481,-0.17362,-0.00001,0.17362,0.98481,1,-0.00001,0.00001)},["Children"]={}}}}},
    ["ElderwoodKnife"] = {["ModelId"]="11262771067",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.276,3.531,1.041),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://11238166013",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.07,0.07,0.07),["TextureId"]="rbxassetid://11238176757",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["ElderwoodKnifeChroma"] = {["ModelId"]="11254975176",["Type"]="Knife",["Chroma"]=true,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.276,3.531,1.041),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://11238166013",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.07,0.07,0.07),["TextureId"]="http://www.roblox.com/asset/?id=11370088878",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,10,0),["Face"]=Enum.NormalId.Right,["Texture"]="rbxassetid://11370095395",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["ElderwoodScythe"] = {["ModelId"]="4211148191",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["DoubleSided"]=false,["Material"]=Enum.Material.Plastic,["MeshId"]="rbxassetid://4217523241",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.28809,3.82182,2.61529),["TextureID"]="http://www.roblox.com/asset/?id=4210044808",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0.10158,0.15964,0.15613,0.999,-0.02982,-0.03345,0.04003,0.92926,0.36726,0.02013,-0.36823,0.92952)},["Children"]={}}}}},
    ["Eternal"] = {["ModelId"]="619605312",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(16,42,220),["Material"]=Enum.Material.DiamondPlate,["Reflectance"]=0.01,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.23,2.7,0.7),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://532155954",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.45,0.45,0.45),["TextureId"]="rbxassetid://532156041",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Eternal2"] = {["ModelId"]="2545253030",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(0,255,0),["Material"]=Enum.Material.DiamondPlate,["Reflectance"]=0.01,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.23,2.7,0.7),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://532155954",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.45,0.45,0.45),["TextureId"]="rbxassetid://2585776718",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Eternal3"] = {["ModelId"]="3279011390",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.25,3.24,0.77),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://532155954",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.47,0.47,0.47),["TextureId"]="rbxassetid://5238664918",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Eternal4"] = {["ModelId"]="4999958740",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.25,3.24,0.77),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://532155954",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.47,0.47,0.47),["TextureId"]="rbxassetid://5222717744",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["EternalCane"] = {["ModelId"]="4488391411",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(16,42,220),["Material"]=Enum.Material.DiamondPlate,["Reflectance"]=0.01,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.23,2.7,0.7),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://3132923779",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.95,0.95,0.95),["TextureId"]="rbxassetid://4488374804",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Fang"] = {["ModelId"]="198442811",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.75,3,0.42),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=117500241",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.4,0.4,0.4),["TextureId"]="http://www.roblox.com/asset/?id=117500388",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,-0.03957,-0.0005,-0.99922,0.01768,0.99984,-0.0012,0.99906,-0.01771,-0.03955)},["Children"]={}}}}},
    ["FangChroma"] = {["ModelId"]="3187392501",["Type"]="Knife",["Chroma"]=true,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(231,231,236),["Material"]=Enum.Material.DiamondPlate,["Reflectance"]=0.01,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.99,3,0.23),["Transparency"]=0},["Children"]={{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,0,0),["Face"]=Enum.NormalId.Front,["Texture"]="rbxassetid://3167057391",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://117500241",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.4,0.37,0.37),["TextureId"]="",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,-0.03957,-0.0005,-0.99922,0.01768,0.99984,-0.0012,0.99906,-0.01771,-0.03955)},["Children"]={}}}}},
    ["Flames"] = {["ModelId"]="585873746",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.25,0.7,2.85),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=238314098",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.6,0.8,0.73),["TextureId"]="http://www.roblox.com/asset/?id=238314124",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Part",["Name"]="EffectCenter",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0.52496,1,0,0,0,0,1,0,-1,0),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.25,0.2,0.2),["Transparency"]=1},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0.00653,0.08929,-0.12036,1,0.00227,-0.00214,0.00189,0.10443,0.99453,0.00248,-0.99453,0.10442)},["Children"]={}}}}},
    ["Flora"] = {["ModelId"]="138204709945147",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0.000032425129708658286,-0.4806722573338291,0.6787832236264311,1,8.49550929160614e-7,-2.345491800781474e-9,-8.494814096593473e-7,0.9999467134475708,0.010325612500309944,1.111749980964305e-8,-0.010325612500309944,0.9999467134475708),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(0.045705114181727347,0.045704772138556,0.0457048),["HeldGripSize"]=Vector3.new(0.58906,1.56705,2.28524),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="MeshPart",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(143,34,34),["DoubleSided"]=true,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://108253816085047",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.58906,1.56705,2.28524),["TextureID"]="rbxassetid://116621225933096",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.20001,0.08992,1,0,0,0,0.64276,0.76607,0,-0.76606,0.64276)},["Children"]={}}}}},
    ["FlowerwoodGun"] = {["ModelId"]="16963894455",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.051891136561108164,0.05186750601638605,0.0518898),["HeldGripSize"]=Vector3.new(0.66524,1.54,2.59449),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="MeshPart",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["DoubleSided"]=false,["Material"]=Enum.Material.Plastic,["MeshId"]="rbxassetid://16895099893",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.66524,1.54,2.59449),["TextureID"]="rbxassetid://16895448237",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.18661,0.12323,1,0,0,0,0.17362,0.98481,0,-0.98481,0.17362)},["Children"]={}}}}},
    ["FlowerwoodKnife"] = {["ModelId"]="16963860501",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(143,34,34),["DoubleSided"]=true,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://16883629972",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.44447,3.95816,1.07334),["TextureID"]="rbxassetid://16895441338",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Frostbite"] = {["ModelId"]="4528484880",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,2.6,0.7),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset?id=4528435571",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(1.1,1.1,1.1),["TextureId"]="rbxassetid://5211130051",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Frostsaber"] = {["ModelId"]="1269580035",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.3,0.85,3.05),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://1192795322",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.55,0.55,0.6),["TextureId"]="rbxassetid://1192795941",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0.00214,0.01834,-0.04645,1,0,0,0,-0.15645,0.98769,0,-0.98769,-0.15645)},["Children"]={}}}}},
    ["Gemstone"] = {["ModelId"]="3183598040",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,3.15,0.8),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://1626714161",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(25,25,25),["TextureId"]="rbxassetid://3183579677",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["GemstoneChroma"] = {["ModelId"]="3183597816",["Type"]="Knife",["Chroma"]=true,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(159,243,233),["Material"]=Enum.Material.DiamondPlate,["Reflectance"]=0.01,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,3,0.7),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://1626714161",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(25,25,25),["TextureId"]="rbxassetid://3183577898",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,10,0),["Face"]=Enum.NormalId.Left,["Texture"]="rbxassetid://3183578044",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Ghostblade"] = {["ModelId"]="4221789003",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.605,1.65,1.01),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://4217554208",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.05,0.05,0.05),["TextureId"]="rbxassetid://5007736173",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Gingerblade"] = {["ModelId"]="2669336659",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(248,248,248),["Material"]=Enum.Material.Fabric,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.25,3,0.5),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://2682453204",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.61,0.61,0.61),["TextureId"]="rbxassetid://2682446647",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["GingerbladeChroma"] = {["ModelId"]="2672349340",["Type"]="Knife",["Chroma"]=true,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(248,248,248),["Material"]=Enum.Material.Fabric,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.25,3,0.5),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://2682453204",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.61,0.61,0.61),["TextureId"]="rbxassetid://2672327402",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,9,0),["Face"]=Enum.NormalId.Front,["Texture"]="rbxassetid://2672332704",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,9,0),["Face"]=Enum.NormalId.Front,["Texture"]="rbxassetid://2672332700",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["GingerLuger"] = {["ModelId"]="2674983099",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(-0.003082275390625,-0.2084674835205078,0.564697265625,0.9986512064933777,-0.027241254225373268,-0.04420004040002823,0.03103393316268921,0.9956790208816528,0.08752333372831345,0.041624803096055984,-0.08877698332071304,0.9951815009117126),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(1.8,1.8,1.8),["HeldGripSize"]=Vector3.new(0.51,1.18,1.35),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(0,143,156),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.51,1.18,1.35),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=95356090",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(1.8,1.8,1.8),["TextureId"]="rbxassetid://2702668339",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0.14999,0.03833,0.33319,1,0,0,0,0,1,0,-1,0)},["Children"]={}}}}},
    ["Gingermint_G"] = {["ModelId"]="11872179646",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.04606,0.04606,0.04606),["HeldGripSize"]=Vector3.new(0.39795,1.02803,2.37765),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.SmoothPlastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.39795,1.02803,2.37765),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://11866444071",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.04606,0.04606,0.04606),["TextureId"]="rbxassetid://11866444253",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(-0.09469,-0.09924,0.23668,0.99179,0.11365,0.05858,-0.11578,0.60394,0.78857,0.05425,-0.78888,0.61214)},["Children"]={}}}}},
    ["Gingermint_K"] = {["ModelId"]="11855306927",["Type"]="Knife",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-1.1977958679199219,2.384185791015625e-7,1,5.239035316684237e-10,-1.2665985593685036e-7,-5.238759426262618e-10,1,2.1792938298403897e-7,1.2665985593685036e-7,-2.1792938298403897e-7,1),["HeldGripCalibrated"]=false,["Model"]={["Class"]="Part",["Name"]="Handle",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Transparency"]=0,["Reflectance"]=0,["Shape"]=Enum.PartType.Block,["Color"]=Color3.fromRGB(17.00000088661909,17.00000088661909,17.00000088661909),["Material"]=Enum.Material.Plastic,["CastShadow"]=true,["Size"]=Vector3.new(0.4000000059604645,3,0.800000011920929)},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["Offset"]=Vector3.new(0,0,0),["VertexColor"]=Vector3.new(1,1,1),["MeshType"]=Enum.MeshType.FileMesh,["Scale"]=Vector3.new(0.057604461908340454,0.05760447308421135,0.057604461908340454),["MeshId"]="rbxassetid://11837984324",["TextureId"]="rbxassetid://11837984504"},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Gingermint_KChroma"] = {["ModelId"]="11873640255",["Type"]="Knife",["Chroma"]=true,["HeldGrip"]=CFrame.new(0,-1.192178726196289,-5.960464477539063e-8,1,1.6996628104948286e-8,-1.0430808572436945e-7,-1.6996631657661965e-8,1,-2.6077017878378683e-8,1.0430808572436945e-7,2.6077019654735523e-8,1),["HeldGripCalibrated"]=false,["Model"]={["Class"]="Part",["Name"]="Handle",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Transparency"]=0,["Reflectance"]=0,["Shape"]=Enum.PartType.Block,["Color"]=Color3.fromRGB(17.00000088661909,17.00000088661909,17.00000088661909),["Material"]=Enum.Material.Plastic,["CastShadow"]=true,["Size"]=Vector3.new(0.4000000059604645,3,0.800000011920929)},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["Offset"]=Vector3.new(0,0,0),["VertexColor"]=Vector3.new(1,1,1),["MeshType"]=Enum.MeshType.FileMesh,["Scale"]=Vector3.new(0.057604461908340454,0.05760447308421135,0.057604461908340454),["MeshId"]="rbxassetid://11837984324",["TextureId"]="rbxassetid://11885808526"},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(0,255,247),["Face"]=Enum.NormalId.Back,["Texture"]="rbxassetid://11883888650",["Transparency"]=0,["ZIndex"]=1},["Children"]={}}}}},
    ["Gingerscope"] = {["ModelId"]="15666469505",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.399998993,0.899999976,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(0.08417284818623448,0.08419816229712668,0.0841742),["HeldGripSize"]=Vector3.new(0.2697,1.25815,4.20871),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="MeshPart",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(143,34,34),["DoubleSided"]=false,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://15374602183",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.2697,1.25815,4.20871),["TextureID"]="rbxassetid://15409041564",["Transparency"]=0},["Children"]={{["Class"]="MeshPart",["Name"]="Scope",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(129,181,204),["DoubleSided"]=false,["Material"]=Enum.Material.Glass,["MeshId"]="rbxassetid://15374679651",["Reflectance"]=1,["RelCF"]=CFrame.new(0,0.48315,0.20723,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.18712,0.18712,1.41355),["TextureID"]="",["Transparency"]=0.35},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0.12991,-0.00003,0.075,1,0,0,0,0.70713,0.70708,0,-0.70708,0.70713)},["Children"]={}}}}},
    ["Gingerscythe_Ancient"] = {["ModelId"]="15683188776",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="Handle",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Transparency"]=0,["Reflectance"]=0,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["CastShadow"]=true,["Size"]=Vector3.new(0.3672752380371094,0.09181880950927734,0.1836376190185547)},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["Offset"]=Vector3.new(0,0,0),["VertexColor"]=Vector3.new(1,1,1),["MeshType"]=Enum.MeshType.FileMesh,["Scale"]=Vector3.new(0.09181880950927734,0.09181880950927734,0.09181880950927734),["MeshId"]="rbxassetid://15395668244",["TextureId"]="rbxassetid://15409146285"},["Children"]={}}}}},
    ["Gingerscythe_Godly"] = {["ModelId"]="15683175970",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="Handle",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Transparency"]=0,["Reflectance"]=0,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["CastShadow"]=true,["Size"]=Vector3.new(0.3672752380371094,0.09181880950927734,0.1836376190185547)},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["Offset"]=Vector3.new(0,0,0),["VertexColor"]=Vector3.new(1,1,1),["MeshType"]=Enum.MeshType.FileMesh,["Scale"]=Vector3.new(0.09181880950927734,0.09181880950927734,0.09181880950927734),["MeshId"]="rbxassetid://15397282571",["TextureId"]="rbxassetid://15397286194"},["Children"]={}}}}},
    ["GreenLuger"] = {["ModelId"]="332044679",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(-0.003082275390625,-0.2084674835205078,0.564697265625,0.9986512064933777,-0.027241254225373268,-0.04420004040002823,0.03103393316268921,0.9956790208816528,0.08752333372831345,0.041624803096055984,-0.08877698332071304,0.9951815009117126),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(1.8,1.8,1.8),["HeldGripSize"]=Vector3.new(0.2,1.83,1.03),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.SmoothPlastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.2,1.83,1.03),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=95356090",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(1.8,1.8,1.8),["TextureId"]="http://www.roblox.com/asset/?id=126534866",["VertexColor"]=Vector3.new(0,1,0)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0.14999,0.03836,0.33319,1,0,0,0,0,1,0,-1,0)},["Children"]={}}}}},
    ["Hallow"] = {["ModelId"]="531878205",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,3,0.7),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset?id=179155055",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.57,0.57,0.57),["TextureId"]="http://www.roblox.com/asset?id=179155105",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Hallowgun"] = {["ModelId"]="5878721461",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(-0.00001556396519163173,-1.32679099994764,0.02689422194998226,-0.012200922705233097,9.103000309096387e-8,0.9999256134033203,1.0430826336005339e-7,1,-8.97640290986601e-8,-0.9999256134033203,1.0320530918761506e-7,-0.012200922705233097),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(0.0408,0.0407998184257822,0.04079952986847695),["HeldGripSize"]=Vector3.new(2.04,1.07989,0.37193),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="MeshPart",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["DoubleSided"]=false,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://5841866437",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(2.04,1.07989,0.37193),["TextureID"]="http://www.roblox.com/asset/?id=5841868338",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(-0.22485,0.04465,0,0,0.99619,-0.08719,0,0.08719,0.99619,1,0,0)},["Children"]={}}}}},
    ["HallowsBlade"] = {["ModelId"]="1132775323",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,3,0.8),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset?id=179155055",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.55,0.55,0.555),["TextureId"]="rbxassetid://1132750758",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Hallowscythe"] = {["ModelId"]="5877016863",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["DoubleSided"]=false,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://5841877975",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.39243,3.54155,2.9425),["TextureID"]="http://www.roblox.com/asset/?id=5841879647",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0.00824,0.0546,0.62405,-0.99868,0.04691,0.02085,0.04573,0.99751,-0.05374,-0.02332,-0.05271,-0.99834)},["Children"]={}}}}},
    ["Harvester"] = {["ModelId"]="7800847534",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,0,1.029893258642575,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(0.05072520013275003,0.050725523183177225,0.05069168059223831),["HeldGripSize"]=Vector3.new(2.24476,0.65492,2.88),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="MeshPart",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["DoubleSided"]=false,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://7775027413",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(2.24476,0.65492,2.88),["TextureID"]="http://www.roblox.com/asset/?id=7775245551",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0.12991,0,0.07501,0.00002,-0.5,-0.86603,1,-0.00004,0.00005,-0.00006,-0.86603,0.5)},["Children"]={}}}}},
    ["Heartblade"] = {["ModelId"]="6413145922",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["DoubleSided"]=false,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://6404140078",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.27948,3.29,1.14654),["TextureID"]="http://www.roblox.com/asset/?id=6413074818",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["HeartWand"] = {["ModelId"]="118334707962654",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(143,34,34),["DoubleSided"]=true,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://77738838473091",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.43272,3.35869,1.91866),["TextureID"]="rbxassetid://76246633927299",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["HeartWandChroma"] = {["ModelId"]="78479059410850",["Type"]="Knife",["Chroma"]=true,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.80402,2.28355,3.46268),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://77738838473091",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.07821,0.07821,0.07821),["TextureId"]="rbxassetid://78842905206144",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,9,0),["Face"]=Enum.NormalId.Left,["Texture"]="rbxassetid://106915560132163",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Heat"] = {["ModelId"]="201238541",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(196,40,28),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,2.9,0.8),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=105333894",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.3,0.3,0.3),["TextureId"]="http://www.roblox.com/asset/?id=105334003",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["HeatChroma"] = {["ModelId"]="3187395238",["Type"]="Knife",["Chroma"]=true,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(16,42,220),["Material"]=Enum.Material.DiamondPlate,["Reflectance"]=0.01,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,3,0.7),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=105333894",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.33,0.33,0.33),["TextureId"]="http://www.roblox.com/asset/?id=105334003",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,10,0),["Face"]=Enum.NormalId.Left,["Texture"]="rbxassetid://3171194830",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Icebeam"] = {["ModelId"]="8311005531",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.7,-0.3,1,0,0,0,0,-1,0,1,0),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.9999999723783362,1.0000000537769993,1.0001835197368603),["HeldGripSize"]=Vector3.new(0.328,2.199,1.09),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="MeshPart",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["DoubleSided"]=false,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://8310908064",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.328,2.199,1.09),["TextureID"]="rbxassetid://8231066536",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Iceblaster"] = {["ModelId"]="6125814417",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(-0.008469562389662061,-0.700000510159269,-0.5460059487973289,1,0,0,0,0,-1,0,1,0),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(0.9999977313705984,0.9999999794834368,0.9999999716452806),["HeldGripSize"]=Vector3.new(0.4432,1.92998,1.02381),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="MeshPart",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["DoubleSided"]=false,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://6125828567",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.4432,1.92998,1.02381),["TextureID"]="rbxassetid://6120563948",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Forward",["Props"]={["RelCF"]=CFrame.new(0,1,0.00003,1,0,0,0,1,0,0,0,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Up",["Props"]={["RelCF"]=CFrame.new(-0.00002,0,1.00003,1,0,0,0,1,0,0,0,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Icebreaker"] = {["ModelId"]="6125729383",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["DoubleSided"]=false,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://6124173614",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.41062,3.07429,1.95539),["TextureID"]="rbxassetid://6124173821",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Icecream"] = {["ModelId"]="87189663191639",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["Reflectance"]=0,["Color"]=Color3.fromRGB(163.00000548362732,162.00000554323196,165.00000536441803),["MeshId"]="rbxassetid://82044527712515",["RelCF"]=CFrame.new(0,0,0,1.0000003576278687,-2.9802322387695312e-8,5.960464477539063e-8,-2.9802322387695312e-8,1.000000238418579,-7.450580596923828e-8,5.960464477539063e-8,-7.450580596923828e-8,1.0000003576278687),["Transparency"]=0,["TextureID"]="",["DoubleSided"]=false,["Material"]=Enum.Material.Plastic,["CastShadow"]=true,["Size"]=Vector3.new(0.8022343516349792,3.3766095638275146,0.9747558832168579)},["Children"]={{["Class"]="SurfaceAppearance",["Name"]="SurfaceAppearance",["Props"]={["MetalnessMap"]="",["NormalMap"]="",["RoughnessMap"]="",["Color"]=Color3.fromRGB(255,255,255),["AlphaMode"]=Enum.AlphaMode.Overlay,["ColorMap"]="rbxassetid://133533169721039"},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["IcecreamChroma"] = {["ModelId"]="87189663191639",["Type"]="Knife",["Chroma"]=true,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,1.862645149230957e-8,0,1.000000238418579,5.587935447692871e-8,1.862645149230957e-8,5.587935447692871e-8,1.0000003576278687),["Transparency"]=0,["Reflectance"]=0,["Shape"]=Enum.PartType.Block,["Color"]=Color3.fromRGB(163.00000548362732,162.00000554323196,165.00000536441803),["Material"]=Enum.Material.Plastic,["CastShadow"]=true,["Size"]=Vector3.new(0.5002673864364624,1.4208340644836426,2.1544973850250244)},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["Offset"]=Vector3.new(0,0,0),["VertexColor"]=Vector3.new(1,1,1),["MeshType"]=Enum.MeshType.FileMesh,["Scale"]=Vector3.new(0.6960147023200989,0.6960147023200989,0.6960147023200989),["MeshId"]="rbxassetid://82044527712515",["TextureId"]="rbxassetid://133533169721039"},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.24657118320465088,0.11084433645009995,1,0,0,0,0.6427633166313171,0.7660649418830872,0,-0.7660649418830872,0.6427633166313171)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Transparency"]=0,["Color3"]=Color3.fromRGB(0,153.35207998752594,255),["Face"]=Enum.NormalId.Left,["ZIndex"]=1,["Texture"]="rbxassetid://98918130519475"},["Children"]={}}}}},
    ["IceDragon"] = {["ModelId"]="585872642",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(99,95,98),["Material"]=Enum.Material.Plastic,["Reflectance"]=0.4,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.35,0.72,2.98),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=165708869 ",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.5,0.5,0.5),["TextureId"]="http://www.roblox.com/asset/?id=165708903 ",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(-0.00896,-0.12686,-0.15436,-0.99993,-0.00781,0.00911,-0.00781,-0.15308,-0.98818,0.00911,-0.98818,0.15301)},["Children"]={}}}}},
    ["Iceflake"] = {["ModelId"]="8304818186",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["DoubleSided"]=false,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://8231045240",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.18449,3.37688,0.82576),["TextureID"]="rbxassetid://8231046270",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["IceHammer_Ancient"] = {["ModelId"]="11855274019",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="Handle",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,0.9999999403953552,0,0,0,0.9999999403953552),["Transparency"]=0,["Reflectance"]=0,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["CastShadow"]=true,["Size"]=Vector3.new(1.024999976158142,3.680999994277954,2.4100000858306885)},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["Offset"]=Vector3.new(0,0,0),["VertexColor"]=Vector3.new(1,1,1),["MeshType"]=Enum.MeshType.FileMesh,["Scale"]=Vector3.new(0.075628861784935,0.07389488071203232,0.07326991111040115),["MeshId"]="rbxassetid://11848711686",["TextureId"]="rbxassetid://11850483027"},["Children"]={}}}}},
    ["Icepiercer"] = {["ModelId"]="11874071041",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(1.1920908645904036e-7,-0.5193492067341179,0.7164066131086604,1,-2.689194822380614e-8,-1.3411037969035533e-7,2.6891960658304015e-8,1,9.499466813167601e-8,1.3411037969035533e-7,-9.499467523710337e-8,1),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(0.05476696915799317,0.05476679637840489,0.054767),["HeldGripSize"]=Vector3.new(2.46939,0.75263,2.73835),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="MeshPart",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["DoubleSided"]=false,["Material"]=Enum.Material.Plastic,["MeshId"]="rbxassetid://11868991644",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(2.46939,0.75263,2.73835),["TextureID"]="rbxassetid://11869075814",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0.12988,0,0.07498,0.00002,-0.5,-0.86603,1,-0.00004,0.00005,-0.00006,-0.86603,0.5)},["Children"]={}}}}},
    ["IceShard"] = {["ModelId"]="1268710824",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["Material"]=Enum.Material.DiamondPlate,["Reflectance"]=0.01,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,3,0.7),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=188539751",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.85,0.85,0.85),["TextureId"]="http://www.roblox.com/asset/?id=188539820",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(-0.01,-0.13699,-0.17639,0.99782,-0.06573,-0.00656,0.00088,-0.08616,0.99628,-0.06605,-0.99411,-0.08592)},["Children"]={}}}}},
    ["Icewing"] = {["ModelId"]="3183085102",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.40003,4.05,1.8),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://3183449780",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.085,0.085,0.085),["TextureId"]="rbxassetid://2279588369",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0.0031,-0.00953,0.2059,-0.99976,0.01674,0.01386,0.02037,0.9442,0.32875,-0.00759,0.32896,-0.94431)},["Children"]={}}}}},
    ["Jinglegun"] = {["ModelId"]="6125742758",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.7,-0.3,1,0,0,0,0,-1,0,1,0),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(1,1,1),["HeldGripSize"]=Vector3.new(0.751,1.799,1.175),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.751,1.799,1.175),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://6125843704",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(1,1,1),["TextureId"]="rbxassetid://6125843755",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Laser"] = {["ModelId"]="238546983",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.10000000149011612,0.699999988079071,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(0.5,0.5,0.5),["HeldGripSize"]=Vector3.new(0.51,1.18,1.35),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(0,143,156),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.51,1.18,1.35),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset?id=130099641",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.5,0.5,0.5),["TextureId"]="http://www.roblox.com/asset?id=161254231",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["LaserChroma"] = {["ModelId"]="3187395952",["Type"]="Gun",["Chroma"]=true,["HeldGrip"]=CFrame.new(0,-0.10000000149011612,0.699999988079071,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(0.5,0.5,0.5),["HeldGripSize"]=Vector3.new(0.51,1.18,1.35),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(0,143,156),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.51,1.18,1.35),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://130099641",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.5,0.5,0.5),["TextureId"]="",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,10,0),["Face"]=Enum.NormalId.Left,["Texture"]="rbxassetid://3171220436",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Lightbringer"] = {["ModelId"]="4749070432",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0.03159497306743495,-0.4226497632152278,0.5181302729754351,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(0.039,0.039,0.039),["HeldGripSize"]=Vector3.new(0.398,1.62,1.964),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.398,1.62,1.964),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://4730813852",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.039,0.039,0.039),["TextureId"]="http://www.roblox.com/asset/?id=4728487789",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.1866,0.12323,1,0,0,0,0.17362,0.98481,0,-0.98481,0.17362)},["Children"]={}}}}},
    ["Logchopper"] = {["ModelId"]="4535644282",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,3,0.7),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset?id=4535643726",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.96,0.96,0.96),["TextureId"]="rbxassetid://5211110240",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Luger"] = {["ModelId"]="198042673",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(-0.003082275390625,-0.2084674835205078,0.564697265625,0.9986512064933777,-0.027241254225373268,-0.04420004040002823,0.03103393316268921,0.9956790208816528,0.08752333372831345,0.041624803096055984,-0.08877698332071304,0.9951815009117126),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(1.8,1.8,1.8),["HeldGripSize"]=Vector3.new(0.51,1.18,1.35),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(0,143,156),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.51,1.18,1.35),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=95356090",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(1.8,1.8,1.8),["TextureId"]="http://www.roblox.com/asset/?id=126534866",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0.15,0.03836,0.33322,1,0,0,0,0,1,0,-1,0)},["Children"]={}}}}},
    ["Lugercane"] = {["ModelId"]="4535482609",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(-0.003082275390625,-0.2084674835205078,0.564697265625,0.9986512064933777,-0.027241254225373268,-0.04420004040002823,0.03103393316268921,0.9956790208816528,0.08752333372831345,0.041624803096055984,-0.08877698332071304,0.9951815009117126),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(1.8,1.8,1.8),["HeldGripSize"]=Vector3.new(0.51,1.18,1.35),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(0,143,156),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.51,1.18,1.35),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://95356090",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(1.8,1.8,1.8),["TextureId"]="rbxassetid://4835358188",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.18655,0.12321,1,0,0,0,0.17362,0.98481,0,-0.98481,0.17362)},["Children"]={}}}}},
    ["LugerChroma"] = {["ModelId"]="3187395551",["Type"]="Gun",["Chroma"]=true,["HeldGrip"]=CFrame.new(-0.003082275390625,-0.2084674835205078,0.564697265625,0.9986512064933777,-0.027241254225373268,-0.04420004040002823,0.03103393316268921,0.9956790208816528,0.08752333372831345,0.041624803096055984,-0.08877698332071304,0.9951815009117126),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(1.8,1.8,1.8),["HeldGripSize"]=Vector3.new(0.51,1.18,1.35),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(0,143,156),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.51,1.18,1.35),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://95356090",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(1.8,1.8,1.8),["TextureId"]="",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,9,0),["Face"]=Enum.NormalId.Back,["Texture"]="rbxassetid://3171206966",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0.15,0.03835,0.33322,1,0,0,0,0,1,0,-1,0)},["Children"]={}}}}},
    ["Makeshift"] = {["ModelId"]="11229837140",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.4075697280761122,1.0676403278216942,1,5.441189543375913e-8,-2.469291189299838e-7,-5.4411874117477055e-8,1,8.940691742509443e-8,2.469291189299838e-7,-8.940690321423972e-8,1),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(0.05462963650952727,0.05461925952299158,0.054628995832138386),["HeldGripSize"]=Vector3.new(0.58832,1.25,2.73145),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="MeshPart",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["DoubleSided"]=false,["Material"]=Enum.Material.Plastic,["MeshId"]="rbxassetid://11158364935",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.58832,1.25,2.73145),["TextureID"]="http://www.roblox.com/asset/?id=11274360089",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.19998,0.08992,1,0,0,0,0.64276,0.76607,0,-0.76607,0.64276)},["Children"]={}}}}},
    ["Minty"] = {["ModelId"]="4535408229",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,0.35,0.7,-1,0,0,0,-1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(1.119044817204301,1.1190461058678443,1.1190482862099345),["HeldGripSize"]=Vector3.new(0.33348,1.35042,1.88001),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="MeshPart",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["DoubleSided"]=false,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://4528424409",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.33348,1.35042,1.88001),["TextureID"]="rbxassetid://4528424475",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(-0.05,-0.07257,0.23923,-1,0,0,0,0,-1,0,-1,0)},["Children"]={}}}}},
    ["Nebula"] = {["ModelId"]="6598123521",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["DoubleSided"]=false,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://6596839942",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.31685,3.4062,1.15913),["TextureID"]="http://www.roblox.com/asset/?id=6256756879",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Nightblade"] = {["ModelId"]="475478854",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(99,95,98),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.2,3.1,0.6),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=103838505",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.7,0.45,0.5),["TextureId"]="http://www.roblox.com/asset/?id=103838996",["VertexColor"]=Vector3.new(0.4,0.4,0.4)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0.00607,0.15098,0.04654,0.99999,0.00282,-0.00272,-0.00304,0.9962,-0.0871,0.00246,0.08711,0.9962)},["Children"]={}}}}},
    ["NikKnife"] = {["ModelId"]="2533351841",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.DiamondPlate,["Reflectance"]=0.01,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,3,0.8),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=305826272",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(1,1,1),["TextureId"]="rbxassetid://2533345412",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Ocean_G"] = {["ModelId"]="13945898892",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(-0.020199707482748647,-0.15266264420952433,0.5821669053112432,1,-1.3436870460736827e-7,-7.619339044140361e-7,1.3436870460736827e-7,1,4.436212286407226e-9,7.619339044140361e-7,-4.4363148710147016e-9,1),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(0.07872,0.04308,0.04678),["HeldGripSize"]=Vector3.new(0.03,0.23,0.05387),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.03,0.23,0.05387),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://13928587755",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.07872,0.04308,0.04678),["TextureId"]="rbxassetid://13928590054",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.19999,0.08994,1,0,0,0,0.64276,0.76607,0,-0.76607,0.64276)},["Children"]={}}}}},
    ["OrangeSeer"] = {["ModelId"]="3184124504",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.5,3.1,1),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset?id=156092238",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.7,0.91,1),["TextureId"]="rbxassetid://3184063179",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Pearl_G"] = {["ModelId"]="18322646152",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.043096294599435,0.04309630319989786,0.0430964),["HeldGripSize"]=Vector3.new(0.56846,1.38161,2.15482),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="MeshPart",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["DoubleSided"]=false,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://18280804203",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.56846,1.38161,2.15482),["TextureID"]="rbxassetid://18280805635",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.20001,0.08991,1,0,0,0,0.64276,0.76607,0,-0.76607,0.64276)},["Children"]={}}}}},
    ["Pearl_K"] = {["ModelId"]="18322621319",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["DoubleSided"]=false,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://18276861801",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.22011,3.48599,0.80767),["TextureID"]="rbxassetid://18276866373",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Peppermint"] = {["ModelId"]="6085035357",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.DiamondPlate,["Reflectance"]=0.01,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,3,0.8),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://6085025295",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0.3,-0.1),["Scale"]=Vector3.new(0.07,0.07,0.07),["TextureId"]="rbxassetid://6074789360",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Pixel"] = {["ModelId"]="473573054",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.DiamondPlate,["Reflectance"]=0.01,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,3,0.8),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=361629844",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(3,3,3),["TextureId"]="http://www.roblox.com/asset/?id=361630114",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(-0.00634,0.03519,-0.22073,0.99817,-0.06049,-0.00075,0.00608,0.08798,0.9961,-0.06019,-0.99428,0.08818)},["Children"]={}}}}},
    ["Plasmabeam"] = {["ModelId"]="10014717343",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.23204932054387503,0.6156195055121017,1,7.798573165018752e-7,1.920627141771547e-7,-7.798569185979431e-7,1,-0.0000019371491362107918,-1.9206422052775451e-7,0.0000019371489088371163,1),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(0.04235,0.04632,0.04392),["HeldGripSize"]=Vector3.new(0.36561,1.17183,2.1575),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.36561,1.17183,2.1575),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://9702755186",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.04235,0.04632,0.04392),["TextureId"]="rbxassetid://10015208201",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0.06429,0.05646,0.19186,1,0,0,0,0.29232,0.95632,0,-0.95632,0.29232)},["Children"]={}}}}},
    ["Prismatic"] = {["ModelId"]="5360359935",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.425,1.90227,1.21),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://5355753728",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.06,0.06917,0.06),["TextureId"]="rbxassetid://5355747943",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Pumpking"] = {["ModelId"]="1138143590",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["Material"]=Enum.Material.DiamondPlate,["Reflectance"]=0.01,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,4.5,0.7),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=94840342",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.4,0.4,0.4),["TextureId"]="rbxassetid://1164426571",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["PurpleSeer"] = {["ModelId"]="3184125244",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.5,3.1,1),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset?id=156092238",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.7,0.91,1),["TextureId"]="rbxassetid://3184063317",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Rainbow_G"] = {["ModelId"]="12966354606",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.36191759316,0.9062288386,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(0.05187686881846597,0.05189273375449638,0.051892796040893856),["HeldGripSize"]=Vector3.new(0.42839,1.21989,2.59464),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="MeshPart",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["DoubleSided"]=false,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://12921221200",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.42839,1.21989,2.59464),["TextureID"]="rbxassetid://12921231088",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.19998,0.08991,1,0,0,0,0.64276,0.76607,0,-0.76607,0.64276)},["Children"]={}}}}},
    ["Rainbow_K"] = {["ModelId"]="12966184630",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["DoubleSided"]=false,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://12921240966",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.26142,3.2611,1.00893),["TextureID"]="rbxassetid://12921241867",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Raygun"] = {["ModelId"]="139431943195380",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.04710763181685582,0.04710768302054529,0.04710760359402493),["HeldGripSize"]=Vector3.new(0.69024,1.64298,2.35538),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="MeshPart",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["DoubleSided"]=false,["Material"]=Enum.Material.Slate,["MeshId"]="rbxassetid://115447220952926",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.69024,1.64298,2.35538),["TextureID"]="rbxassetid://127881437685243",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.20001,0.08994,1,0,0,0,0.64276,0.76607,0,-0.76607,0.64276)},["Children"]={}}}}},
    ["RaygunChroma"] = {["ModelId"]="139431943195380",["Type"]="Gun",["Chroma"]=true,["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.0472,0.0472,0.0472),["HeldGripSize"]=Vector3.new(0.69,1.643,2.355),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Glass,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.69,1.643,2.355),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://115447220952926",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.0472,0.0472,0.0472),["TextureId"]="rbxassetid://127881437685243",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,10,0),["Face"]=Enum.NormalId.Left,["Texture"]="rbxassetid://73231950532216",["Transparency"]=0,["ZIndex"]=0},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.20004,0.08991,1,0,0,0,0.64276,0.76607,0,-0.76607,0.64276)},["Children"]={}}}}},
    ["Reaver_Ancient"] = {["ModelId"]="7791640819",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="Reaver (Ancient) MM2",["Props"]={["Reflectance"]=0,["Color"]=Color3.fromRGB(163,162,165),["MeshId"]="rbxassetid://7774148738",["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Transparency"]=0,["TextureID"]="rbxassetid://7774148967",["Material"]=Enum.Material.Plastic,["CastShadow"]=true,["Size"]=Vector3.new(1.033421516418457,4.225603103637695,4.082431316375732)},["Children"]={}}},
    ["RedLuger"] = {["ModelId"]="332044583",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(-0.003082275390625,-0.2084674835205078,0.564697265625,0.9986512064933777,-0.027241254225373268,-0.04420004040002823,0.03103393316268921,0.9956790208816528,0.08752333372831345,0.041624803096055984,-0.08877698332071304,0.9951815009117126),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(1.8,1.8,1.8),["HeldGripSize"]=Vector3.new(0.51,1.18,1.35),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(0,143,156),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.51,1.18,1.35),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=95356090",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(1.8,1.8,1.8),["TextureId"]="http://www.roblox.com/asset/?id=126534866",["VertexColor"]=Vector3.new(1,0.2,0.3)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0.15,0.03833,0.33322,1,0,0,0,0,1,0,-1,0)},["Children"]={}}}}},
    ["RedSeer"] = {["ModelId"]="3184122829",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.5,3.1,1),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset?id=156092238",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.7,0.91,1),["TextureId"]="rbxassetid://3184063443",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Sakura_K"] = {["ModelId"]="12339366064",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["DoubleSided"]=false,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://12307707430",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.52985,3.70591,0.52184),["TextureID"]="rbxassetid://12307707797",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Sands"] = {["ModelId"]="119213058412452",["Type"]="Gun",["Chroma"]=false,["Placement"]="WaistRight",["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.037926,0.037926,0.037926),["HeldGripSize"]=Vector3.new(0.389873,1.107298,1.679064),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["Size"]=Vector3.new(0.389873,1.107298,1.679064),["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Color"]=Color3.fromRGB(163.00000350000002,161.99999549999998,164.99999400000002),["Material"]=Enum.Material.Plastic,["Shape"]=Enum.PartType.Block,["Reflectance"]=0,["Transparency"]=0,["CastShadow"]=true},["Children"]={{["Class"]="SpecialMesh",["Name"]="ChromaScanV2Mesh",["Props"]={["MeshType"]=Enum.MeshType.FileMesh,["MeshId"]="rbxassetid://104658283027428",["TextureId"]="rbxassetid://138720590976364",["Scale"]=Vector3.new(0.037926,0.037926,0.037926),["Offset"]=Vector3.new(0,0,0),["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.19216,0.086384,1,0,0,0,0.642763,0.766065,0,-0.766065,0.642763)},["Children"]={}}}}},
    ["SandsChroma"] = {["ModelId"]="119213058412452",["Type"]="Gun",["Chroma"]=true,["Placement"]="WaistRight",["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.037926,0.037926,0.037926),["HeldGripSize"]=Vector3.new(0.389873,1.107298,1.679064),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["Size"]=Vector3.new(0.389873,1.107298,1.679064),["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Color"]=Color3.fromRGB(163.00000350000002,161.99999549999998,164.99999400000002),["Material"]=Enum.Material.Plastic,["Shape"]=Enum.PartType.Block,["Reflectance"]=0,["Transparency"]=0,["CastShadow"]=true},["Children"]={{["Class"]="SpecialMesh",["Name"]="ChromaScanV2Mesh",["Props"]={["MeshType"]=Enum.MeshType.FileMesh,["MeshId"]="rbxassetid://104658283027428",["TextureId"]="rbxassetid://92831262223446",["Scale"]=Vector3.new(0.037926,0.037926,0.037926),["Offset"]=Vector3.new(0,0,0),["VertexColor"]=Vector3.new(1,1,1)},["Attributes"]={["CartiHubChromaMesh"]=true},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.19216,0.086384,1,0,0,0,0.642763,0.766065,0,-0.766065,0.642763)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Texture"]="rbxassetid://92831262223446",["Transparency"]=0,["Face"]=Enum.NormalId.Front,["Color3"]=Color3.fromRGB(255,255,255)},["Children"]={}}}}},
    ["Saw"] = {["ModelId"]="235381341",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["Material"]=Enum.Material.DiamondPlate,["Reflectance"]=0.01,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,3,0.8),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset?id=168119698",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.5,0.5,0.5),["TextureId"]="http://www.roblox.com/asset?id=168119736",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["SawChroma"] = {["ModelId"]="3187392992",["Type"]="Knife",["Chroma"]=true,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.25,3.08,1),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://168119698",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.5,0.5,0.55),["TextureId"]="rbxassetid://3171086347",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,9,0),["Face"]=Enum.NormalId.Left,["Texture"]="rbxassetid://3171091036",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Scythe"] = {["ModelId"]="2511791893",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.25,2.9,1.6),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=305826272",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(1,1,1),["TextureId"]="rbxassetid://2511673515",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["SeerChroma"] = {["ModelId"]="3184125538",["Type"]="Knife",["Chroma"]=true,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,3,0.7),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://156092238",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.7,0.91,1),["TextureId"]="rbxassetid://3184059718",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,10,0),["Face"]=Enum.NormalId.Front,["Texture"]="rbxassetid://3184061374",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Shark"] = {["ModelId"]="203858533",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.1,0.75,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(0.44,0.44,0.44),["HeldGripSize"]=Vector3.new(0.58,1.34,2.48),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.58,1.34,2.48),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=118269783",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.44,0.44,0.44),["TextureId"]="rbxassetid://1106696354",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(-0.00634,0.03519,-0.22076,0.99817,-0.06049,-0.00075,0.00608,0.08798,0.9961,-0.06019,-0.99428,0.08818)},["Children"]={}}}}},
    ["SharkChroma"] = {["ModelId"]="3187395738",["Type"]="Gun",["Chroma"]=true,["HeldGrip"]=CFrame.new(0,-0.1,0.75,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(0.44,0.44,0.44),["HeldGripSize"]=Vector3.new(0.8,1.02,2.07),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.8,1.02,2.07),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://118269783",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.44,0.44,0.44),["TextureId"]="rbxassetid://3171214838",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,18,0),["Face"]=Enum.NormalId.Back,["Texture"]="rbxassetid://3171214969",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0.15,-0.24356,0.23059,1,0,0,0,0,1,0,-1,0)},["Children"]={}}}}},
    ["Slasher"] = {["ModelId"]="315506122",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["Material"]=Enum.Material.DiamondPlate,["Reflectance"]=0.01,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,3.17,0.7),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=283709822",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.45,0.45,0.45),["TextureId"]="http://www.roblox.com/asset/?id=313894904",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["SlasherChroma"] = {["ModelId"]="3187393285",["Type"]="Knife",["Chroma"]=true,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["Material"]=Enum.Material.DiamondPlate,["Reflectance"]=0.01,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,3.17,0.7),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://283709822",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.45,0.45,0.45),["TextureId"]="rbxassetid://3171107559",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,9,0),["Face"]=Enum.NormalId.Back,["Texture"]="rbxassetid://3171107715",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Snowcannon"] = {["ModelId"]="129186939023729",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.049990993984320414,0.049991411960399426,0.0499914),["HeldGripSize"]=Vector3.new(0.55858,1.35489,2.49957),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="MeshPart",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["DoubleSided"]=false,["Material"]=Enum.Material.SmoothPlastic,["MeshId"]="rbxassetid://99836890880541",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.55858,1.35489,2.49957),["TextureID"]="rbxassetid://122392330922281",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,0.00003,0.0899,1,0,0,0,0.64276,0.76607,0,-0.76607,0.64276)},["Children"]={}},{["Class"]="MeshPart",["Name"]="Glass",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(248,248,248),["DoubleSided"]=false,["Material"]=Enum.Material.SmoothPlastic,["MeshId"]="rbxassetid://127037890709284",["Reflectance"]=0,["RelCF"]=CFrame.new(-915.88696,1985.51025,2664.40527,-0.88933,-0.25869,-0.37707,-0.25617,-0.40121,0.87944,-0.37879,0.8787,0.29054),["Size"]=Vector3.new(0.46142,0.46142,1.40329),["TextureID"]="",["Transparency"]=0.8},["Children"]={}}}}},
    ["SnowcannonChroma"] = {["ModelId"]="129186939023729",["Type"]="Gun",["Chroma"]=true,["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.04964,0.04964,0.04964),["HeldGripSize"]=Vector3.new(0.559,1.355,2.5),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.559,1.355,2.5),["Transparency"]=0},["Children"]={{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,0,0),["Face"]=Enum.NormalId.Left,["Texture"]="rbxassetid://84894022221722",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.25153,0.11305,1,0,0,0,0.64276,0.76607,0,-0.76607,0.64276)},["Children"]={}},{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://99836890880541",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.04964,0.04964,0.04964),["TextureId"]="rbxassetid://122392330922281",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}}}}},
    ["SnowDagger"] = {["ModelId"]="95328449981238",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["DoubleSided"]=false,["Material"]=Enum.Material.Plastic,["MeshId"]="rbxassetid://140633396635861",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.36039,2.99009,0.71375),["TextureID"]="rbxassetid://77812964601215",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["SnowDaggerChroma"] = {["ModelId"]="95328449981238",["Type"]="Knife",["Chroma"]=true,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.33126,2.75126,0.65699),["Transparency"]=0},["Children"]={{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,9,0),["Face"]=Enum.NormalId.Left,["Texture"]="rbxassetid://109403096491788",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://140633396635861",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.05978,0.05978,0.05978),["TextureId"]="rbxassetid://77812964601215",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Snowflake"] = {["ModelId"]="1268932977",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(16,42,220),["Material"]=Enum.Material.DiamondPlate,["Reflectance"]=0.01,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,3.79,0.86),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://582120569",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.6,0.6,0.6),["TextureId"]="rbxassetid://582120836",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["SnowstormChroma"] = {["ModelId"]="70973050894155",["Type"]="Knife",["Chroma"]=true,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.26,3.852,0.958),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://86944837615327",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.07705,0.07705,0.07705),["TextureId"]="rbxassetid://86253759560362",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,0,0),["Face"]=Enum.NormalId.Left,["Texture"]="rbxassetid://118939212650553",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Spectre2022"] = {["ModelId"]="11229779932",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.05246,0.05246,0.05246),["HeldGripSize"]=Vector3.new(0.2,1.83,1.03),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.SmoothPlastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.2,1.83,1.03),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://11165536294",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.05246,0.05246,0.05246),["TextureId"]="rbxassetid://11165715120",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Spider"] = {["ModelId"]="473571549",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["Material"]=Enum.Material.DiamondPlate,["Reflectance"]=0.01,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,3,0.8),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=302165984",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.6,0.6,0.6),["TextureId"]="rbxassetid://7596177341",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(-0.00147,0.08734,-0.12192,0.99817,-0.06049,-0.00075,0.00608,0.08798,0.9961,-0.06019,-0.99428,0.08818)},["Children"]={}}}}},
    ["Sugar"] = {["ModelId"]="332848695",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(-0.08333331595,0.4467787842,0.8990923564,-1,0,0,0,-1,0,0,0,1),["HeldGripCalibrated"]=false,["HeldGripScale"]=Vector3.new(0.5,0.5,0.5),["HeldGripSize"]=Vector3.new(0.2,1,1.9),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(196,40,28),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.2,1,1.9),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=101086719",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.5,0.5,0.5),["TextureId"]="http://www.roblox.com/asset/?id=101086650",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(-0.1,0.28233,0.30722,-1,0,0,0,-0.08713,-0.9962,0,-0.9962,0.08713)},["Children"]={}}}}},
    ["SunsetGun"] = {["ModelId"]="129480661108374",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.04585,0.04585,0.04585),["HeldGripSize"]=Vector3.new(0.459,1.355,2.346),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.459,1.355,2.346),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://109742397574153",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.04585,0.04585,0.04585),["TextureId"]="rbxassetid://71731808219690",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(2555,2322,200),["Face"]=Enum.NormalId.Left,["Texture"]="rbxassetid://122480499480858",["Transparency"]=1,["ZIndex"]=1},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.19998,0.0899,1,0,0,0,0.64276,0.76607,0,-0.76607,0.64276)},["Children"]={}}}}},
    ["SunsetGunChroma"] = {["ModelId"]="129480661108374",["Type"]="Gun",["Chroma"]=true,["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.0471,0.0471,0.0471),["HeldGripSize"]=Vector3.new(0.48417,1.37511,2.08516),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.48417,1.37511,2.08516),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://109742397574153",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.0471,0.0471,0.0471),["TextureId"]="rbxassetid://71731808219690",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.19998,0.08992,1,0,0,0,0.64276,0.76607,0,-0.76607,0.64276)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,10,0),["Face"]=Enum.NormalId.Left,["Texture"]="rbxassetid://87234234470516",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Decal",["Name"]="Glow",["Props"]={["Color3"]=Color3.fromRGB(2555,2322,200),["Face"]=Enum.NormalId.Left,["Texture"]="rbxassetid://122480499480858",["Transparency"]=1,["ZIndex"]=2},["Children"]={}}}}},
    ["SunsetKnife"] = {["ModelId"]="103526268515240",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.23611,3.866,1.18362),["Transparency"]=0},["Children"]={{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(2555,2322,200),["Face"]=Enum.NormalId.Left,["Texture"]="rbxassetid://95001575076131",["Transparency"]=1,["ZIndex"]=1},["Children"]={}},{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://137082284051764",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.07391,0.07391,0.07391),["TextureId"]="rbxassetid://93782017269677",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["SunsetKnifeChroma"] = {["ModelId"]="103526268515240",["Type"]="Knife",["Chroma"]=true,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.276,3.531,1.041),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://137082284051764",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.07,0.07,0.07),["TextureId"]="rbxassetid://93782017269677",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,0,0),["Face"]=Enum.NormalId.Right,["Texture"]="rbxassetid://70538223885127",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Decal",["Name"]="Glow",["Props"]={["Color3"]=Color3.fromRGB(2555,2322,200),["Face"]=Enum.NormalId.Left,["Texture"]="rbxassetid://95001575076131",["Transparency"]=1,["ZIndex"]=2},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["SweetChroma"] = {["ModelId"]="126937716954396",["Type"]="Knife",["Chroma"]=true,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.71067,2.0184,3.06062),["Transparency"]=0},["Children"]={{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,10,0),["Face"]=Enum.NormalId.Left,["Texture"]="rbxassetid://87741741305052",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://88250692342609",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.06913,0.06913,0.06913),["TextureId"]="rbxassetid://120707737118924",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["SwirlyAxe"] = {["ModelId"]="8304801000",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["DoubleSided"]=false,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://8293463844",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.51346,2.89648,2.66),["TextureID"]="rbxassetid://8293464070",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["SwirlyBlade"] = {["ModelId"]="8304805693",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["DoubleSided"]=false,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://8302964090",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.46908,3.34704,0.85579),["TextureID"]="rbxassetid://8302965681",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["SwirlyGun"] = {["ModelId"]="8305264097",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.7,-0.3,1,0,0,0,0,-1,0,1,0),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.9999999750905968,0.9999999864780328,1.0000000115948247),["HeldGripSize"]=Vector3.new(0.469,2.539,1.1515),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="MeshPart",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["DoubleSided"]=false,["Material"]=Enum.Material.Plastic,["MeshId"]="rbxassetid://8310911339",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.469,2.539,1.1515),["TextureID"]="rbxassetid://8293539377",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["SwirlyGunChroma"] = {["ModelId"]="8311393414",["Type"]="Gun",["Chroma"]=true,["HeldGrip"]=CFrame.new(0,-0.7,-0.3,1,0,0,0,0,-1,0,1,0),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(1,1,1),["HeldGripSize"]=Vector3.new(1.04973,3.2087,1.6),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(1.04973,3.2087,1.6),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://8310911339",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(1,1,1),["TextureId"]="rbxassetid://10044501316",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,10,0),["Face"]=Enum.NormalId.Front,["Texture"]="rbxassetid://10044507532",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["TheSeer"] = {["ModelId"]="198441783",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.5,3.1,1),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset?id=156092238",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.7,0.91,1),["TextureId"]="http://www.roblox.com/asset?id=156092253 ",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Tides"] = {["ModelId"]="473569625",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["Material"]=Enum.Material.DiamondPlate,["Reflectance"]=0.01,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,3,0.8),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=238314382",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.7,0.9,0.7),["TextureId"]="http://www.roblox.com/asset/?id=238314431",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(-0.0034,0.12729,-0.21518,0.99799,-0.06327,-0.00357,0.00363,0.00083,0.99999,-0.06326,-0.998,0.00106)},["Children"]={}}}}},
    ["TidesChroma"] = {["ModelId"]="3187394934",["Type"]="Knife",["Chroma"]=true,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.45,0.7,3.05),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://238314382",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.7,0.9,0.7),["TextureId"]="rbxassetid://3171168641",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,18,0),["Face"]=Enum.NormalId.Back,["Texture"]="rbxassetid://3171161741",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(-0.0034,0.12729,-0.21515,0.99799,-0.06327,-0.00357,0.00363,0.00083,0.99999,-0.06326,-0.998,0.00106)},["Children"]={}}}}},
    ["TravelerAxe"] = {["ModelId"]="15070870271",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["DoubleSided"]=false,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://15057341638",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.60441,3.406,2.18736),["TextureID"]="rbxassetid://15057460725",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["TravelerGun"] = {["ModelId"]="15091442039",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.04912499489722157,0.04910123309043079,0.0491010037461093),["HeldGripSize"]=Vector3.new(0.48155,1.26318,2.45505),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="MeshPart",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["DoubleSided"]=false,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://15090814396",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.48155,1.26318,2.45505),["TextureID"]="rbxassetid://15090814672",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["TravelerGunChroma"] = {["ModelId"]="15097897227",["Type"]="Gun",["Chroma"]=true,["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.04839,0.0491,0.04924),["HeldGripSize"]=Vector3.new(0.57198,0.52873,2.52),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.57198,0.52873,2.52),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://15090814396",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.04839,0.0491,0.04924),["TextureId"]="rbxassetid://15090814672",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,10,0),["Face"]=Enum.NormalId.Top,["Texture"]="rbxassetid://138224985315804",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Treat"] = {["ModelId"]="131626924640663",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.05389931065615046,0.05389929675547244,0.053899325964599815),["HeldGripSize"]=Vector3.new(0.4485287070274353,1.34443199634552,1.8994859457015991),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="MeshPart",["Name"]="GunDisplay",["Props"]={["Reflectance"]=0,["Color"]=Color3.fromRGB(163.00000548362732,162.00000554323196,165.00000536441803),["MeshId"]="rbxassetid://135790480817772",["RelCF"]=CFrame.new(0,0,0,1.000000238418579,0,-2.9802322387695312e-8,0,1.0000003576278687,1.043081283569336e-7,-2.9802322387695312e-8,1.043081283569336e-7,1.0000004768371582),["Transparency"]=0,["TextureID"]="",["DoubleSided"]=false,["Material"]=Enum.Material.Plastic,["CastShadow"]=true,["Size"]=Vector3.new(0.4485287070274353,1.34443199634552,1.8994859457015991)},["Children"]={{["Class"]="SurfaceAppearance",["Name"]="SurfaceAppearance",["Props"]={["MetalnessMap"]="",["NormalMap"]="",["RoughnessMap"]="",["Color"]=Color3.fromRGB(255,255,255),["AlphaMode"]=Enum.AlphaMode.Overlay,["ColorMap"]="rbxassetid://108067764674565"},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.20000000298023224,0.08990859985351562,1,0,0,0,0.6427633166313171,0.7660649418830872,0,-0.7660649418830872,0.6427633166313171)},["Children"]={}}}}},
    ["TreatChroma"] = {["ModelId"]="131626924640663",["Type"]="Gun",["Chroma"]=true,["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.05384,0.05384,0.05384),["HeldGripSize"]=Vector3.new(0.55352,1.57208,2.38384),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.55352,1.57208,2.38384),["Transparency"]=0},["Children"]={{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,10,0),["Face"]=Enum.NormalId.Left,["Texture"]="rbxassetid://71260815789113",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.20004,0.08987,1,0,0,0,0.64276,0.76607,0,-0.76607,0.64276)},["Children"]={}},{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://135790480817772",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.05384,0.05384,0.05384),["TextureId"]="rbxassetid://86649236464456",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}}}}},
    ["TreeGun2023"] = {["ModelId"]="15682703596",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.020457305441424312,0.020457329202621093,0.020457280401776454),["HeldGripSize"]=Vector3.new(0.83339,1.38372,2.5195),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="MeshPart",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["DoubleSided"]=false,["Material"]=Enum.Material.Plastic,["MeshId"]="rbxassetid://15408863676",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.83339,1.38372,2.5195),["TextureID"]="rbxassetid://15408849730",["Transparency"]=0},["Children"]={{["Class"]="MeshPart",["Name"]="Lights",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(248,217,109),["DoubleSided"]=false,["Material"]=Enum.Material.Neon,["MeshId"]="rbxassetid://15408864622",["Reflectance"]=0,["RelCF"]=CFrame.new(-0.08533,0.1557,-0.32174,0.99472,0.0493,0.08997,-0.04759,0.99865,-0.02099,-0.09088,0.0166,0.99572),["Size"]=Vector3.new(0.72726,0.83294,1.26788),["TextureID"]="",["Transparency"]=0},["Children"]={}},{["Class"]="MeshPart",["Name"]="Lights",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(248,217,109),["DoubleSided"]=false,["Material"]=Enum.Material.Neon,["MeshId"]="rbxassetid://15408864712",["Reflectance"]=0,["RelCF"]=CFrame.new(-0.04137,0.15601,-0.25344,0.99472,0.0493,0.08997,-0.04759,0.99865,-0.02099,-0.09088,0.0166,0.99572),["Size"]=Vector3.new(0.64613,0.7764,1.10341),["TextureID"]="",["Transparency"]=0},["Children"]={}},{["Class"]="MeshPart",["Name"]="Lights",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(248,217,109),["DoubleSided"]=false,["Material"]=Enum.Material.Neon,["MeshId"]="rbxassetid://15408864833",["Reflectance"]=0,["RelCF"]=CFrame.new(0.00167,0.06058,-1.00051,0.99472,0.0493,0.08997,-0.04759,0.99865,-0.02099,-0.09088,0.0166,0.99572),["Size"]=Vector3.new(0.05203,0.09871,0.06772),["TextureID"]="",["Transparency"]=0},["Children"]={}},{["Class"]="MeshPart",["Name"]="Lights",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(248,217,109),["DoubleSided"]=false,["Material"]=Enum.Material.Neon,["MeshId"]="rbxassetid://15408864925",["Reflectance"]=0,["RelCF"]=CFrame.new(0.0848,0.10629,-0.45204,0.99472,0.0493,0.08997,-0.04759,0.99865,-0.02099,-0.09088,0.0166,0.99572),["Size"]=Vector3.new(0.5964,0.87543,1.30518),["TextureID"]="",["Transparency"]=0},["Children"]={}},{["Class"]="MeshPart",["Name"]="Lights",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(248,217,109),["DoubleSided"]=false,["Material"]=Enum.Material.Neon,["MeshId"]="rbxassetid://15408864995",["Reflectance"]=0,["RelCF"]=CFrame.new(0.00178,0.1181,-0.08321,0.99472,0.0493,0.08997,-0.04759,0.99865,-0.02099,-0.09088,0.0166,0.99572),["Size"]=Vector3.new(0.6152,0.84724,0.67052),["TextureID"]="",["Transparency"]=0},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0.00001,-0.20001,0.0899,1,0,0,0,0.64276,0.76607,0,-0.76607,0.64276)},["Children"]={}}}}},
    ["TreeGun2023Chroma"] = {["ModelId"]="15682703596",["Type"]="Gun",["Chroma"]=true,["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.021,0.021,0.0205),["HeldGripSize"]=Vector3.new(0.833,1.384,2.519),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(255,37,0),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.833,1.384,2.519),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://15408863676",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.021,0.021,0.0205),["TextureId"]="",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.19998,0.08992,1,0,0,0,0.64276,0.76607,0,-0.76607,0.64276)},["Children"]={}},{["Class"]="Decal",["Name"]="Decal",["Props"]={["Color3"]=Color3.fromRGB(255,255,255),["Face"]=Enum.NormalId.Front,["Texture"]="rbxassetid://15694616343",["Transparency"]=0.8,["ZIndex"]=1},["Children"]={}},{["Class"]="Decal",["Name"]="Decal",["Props"]={["Color3"]=Color3.fromRGB(255,255,255),["Face"]=Enum.NormalId.Front,["Texture"]="rbxassetid://15694615445",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Model",["Name"]="LightParts",["Props"]={},["Children"]={{["Class"]="MeshPart",["Name"]="LightPart",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(255,255,255),["DoubleSided"]=false,["Material"]=Enum.Material.Neon,["MeshId"]="rbxassetid://15408864622",["Reflectance"]=0,["RelCF"]=CFrame.new(-0.08643,0.19989,-0.21362,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.72726,0.83294,1.26788),["TextureID"]="",["Transparency"]=0},["Children"]={}},{["Class"]="MeshPart",["Name"]="LightPart",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(255,255,255),["DoubleSided"]=false,["Material"]=Enum.Material.Neon,["MeshId"]="rbxassetid://15408864925",["Reflectance"]=0,["RelCF"]=CFrame.new(0.0957,0.15671,-0.32687,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.5964,0.87543,1.30518),["TextureID"]="",["Transparency"]=0},["Children"]={}},{["Class"]="MeshPart",["Name"]="LightPart",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(255,255,255),["DoubleSided"]=false,["Material"]=Enum.Material.Neon,["MeshId"]="rbxassetid://15408864995",["Reflectance"]=0,["RelCF"]=CFrame.new(-0.02002,0.17044,0.03246,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.6152,0.84724,0.67052),["TextureID"]="",["Transparency"]=0},["Children"]={}},{["Class"]="MeshPart",["Name"]="LightPart",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(255,255,255),["DoubleSided"]=false,["Material"]=Enum.Material.Neon,["MeshId"]="rbxassetid://15408864712",["Reflectance"]=0,["RelCF"]=CFrame.new(-0.05078,0.20337,-0.14159,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.64613,0.7764,1.10341),["TextureID"]="",["Transparency"]=0},["Children"]={}},{["Class"]="MeshPart",["Name"]="LightPart",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(255,255,255),["DoubleSided"]=false,["Material"]=Enum.Material.Neon,["MeshId"]="rbxassetid://15408864833",["Reflectance"]=0,["RelCF"]=CFrame.new(0.06543,0.09778,-0.87988,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.05203,0.09871,0.06772),["TextureID"]="",["Transparency"]=0},["Children"]={}}}}}}},
    ["TreeKnife2023"] = {["ModelId"]="15667157715",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(255,0,0),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.41435,4.1435,1.02114),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://15408280573",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.0046,0.0046,0.0046),["TextureId"]="rbxassetid://15408244684",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Model",["Name"]="LightParts",["Props"]={},["Children"]={{["Class"]="MeshPart",["Name"]="LightPart",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(248,217,109),["DoubleSided"]=false,["Material"]=Enum.Material.Neon,["MeshId"]="rbxassetid://15408281396",["Reflectance"]=0,["RelCF"]=CFrame.new(0.00953,-0.00206,-0.15921,0.99954,0.01412,-0.02691,-0.01402,0.9999,0.00364,0.02695,-0.00326,0.99963),["Size"]=Vector3.new(1.0546,2.20523,0.84565),["TextureID"]="",["Transparency"]=0},["Children"]={}},{["Class"]="MeshPart",["Name"]="LightPart",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(248,217,109),["DoubleSided"]=false,["Material"]=Enum.Material.Neon,["MeshId"]="rbxassetid://15408281127",["Reflectance"]=0,["RelCF"]=CFrame.new(0.05166,-0.19347,0.10281,0.99954,0.01412,-0.02691,-0.01402,0.9999,0.00364,0.02695,-0.00326,0.99963),["Size"]=Vector3.new(1.00342,2.14222,1.0312),["TextureID"]="",["Transparency"]=0},["Children"]={}},{["Class"]="MeshPart",["Name"]="LightPart",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(248,217,109),["DoubleSided"]=false,["Material"]=Enum.Material.Neon,["MeshId"]="rbxassetid://15408281298",["Reflectance"]=0,["RelCF"]=CFrame.new(-0.03924,1.17226,-0.05783,0.99954,0.01412,-0.02691,-0.01402,0.9999,0.00364,0.02695,-0.00326,0.99963),["Size"]=Vector3.new(0.11299,0.13324,0.06312),["TextureID"]="",["Transparency"]=0},["Children"]={}},{["Class"]="MeshPart",["Name"]="LightPart",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(248,217,109),["DoubleSided"]=false,["Material"]=Enum.Material.Neon,["MeshId"]="rbxassetid://15408281195",["Reflectance"]=0,["RelCF"]=CFrame.new(0.05583,-0.31531,0.05017,0.99954,0.01412,-0.02691,-0.01402,0.9999,0.00364,0.02695,-0.00326,0.99963),["Size"]=Vector3.new(0.93531,1.86433,0.91616),["TextureID"]="",["Transparency"]=0},["Children"]={}},{["Class"]="MeshPart",["Name"]="LightPart",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(248,217,109),["DoubleSided"]=false,["Material"]=Enum.Material.Neon,["MeshId"]="rbxassetid://15408281466",["Reflectance"]=0,["RelCF"]=CFrame.new(0.0132,-0.6091,0.00861,0.99954,0.01412,-0.02691,-0.01402,0.9999,0.00364,0.02695,-0.00326,0.99963),["Size"]=Vector3.new(1.02064,1.13292,0.87231),["TextureID"]="",["Transparency"]=0},["Children"]={}}}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["TreeKnife2023Chroma"] = {["ModelId"]="15694110573",["Type"]="Knife",["Chroma"]=true,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(255,9,0),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.41435,4.1435,1.02114),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://15408280573",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.0046,0.0046,0.0046),["TextureId"]="",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Decal",["Props"]={["Color3"]=Color3.fromRGB(255,255,255),["Face"]=Enum.NormalId.Front,["Texture"]="rbxassetid://15693337518",["Transparency"]=0.6,["ZIndex"]=1},["Children"]={}},{["Class"]="Decal",["Name"]="Decal",["Props"]={["Color3"]=Color3.fromRGB(255,255,255),["Face"]=Enum.NormalId.Front,["Texture"]="rbxassetid://15693352412",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Model",["Name"]="LightParts",["Props"]={},["Children"]={{["Class"]="MeshPart",["Name"]="LightPart",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(255,255,255),["DoubleSided"]=false,["Material"]=Enum.Material.Neon,["MeshId"]="rbxassetid://15408281396",["Reflectance"]=0,["RelCF"]=CFrame.new(0.0249,0.00073,-0.13696,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(1.0546,2.20523,0.84565),["TextureID"]="",["Transparency"]=0},["Children"]={}},{["Class"]="MeshPart",["Name"]="LightPart",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(255,255,255),["DoubleSided"]=false,["Material"]=Enum.Material.Neon,["MeshId"]="rbxassetid://15408281127",["Reflectance"]=0,["RelCF"]=CFrame.new(0.07666,-0.19095,0.12332,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(1.00342,2.14222,1.0312),["TextureID"]="",["Transparency"]=0},["Children"]={}},{["Class"]="MeshPart",["Name"]="LightPart",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(255,255,255),["DoubleSided"]=false,["Material"]=Enum.Material.Neon,["MeshId"]="rbxassetid://15408281298",["Reflectance"]=0,["RelCF"]=CFrame.new(-0.0376,1.17355,-0.03003,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.11299,0.13324,0.06312),["TextureID"]="",["Transparency"]=0},["Children"]={}},{["Class"]="MeshPart",["Name"]="LightPart",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(255,255,255),["DoubleSided"]=false,["Material"]=Enum.Material.Neon,["MeshId"]="rbxassetid://15408281195",["Reflectance"]=0,["RelCF"]=CFrame.new(0.08155,-0.31226,0.07007,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.93531,1.86433,0.91616),["TextureID"]="",["Transparency"]=0},["Children"]={}},{["Class"]="MeshPart",["Name"]="LightPart",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(255,255,255),["DoubleSided"]=false,["Material"]=Enum.Material.Neon,["MeshId"]="rbxassetid://15408281466",["Reflectance"]=0,["RelCF"]=CFrame.new(0.0415,-0.60669,0.02859,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(1.02064,1.13292,0.87231),["TextureID"]="",["Transparency"]=0},["Children"]={}}}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Turkey2023"] = {["ModelId"]="15413149176",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(1.099,2.812,1.072),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://15320557481",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.056,0.056,0.056),["TextureId"]="rbxassetid://15320558272",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Part",["Name"]="BiteLoad",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(1.099,2.812,1.072),["Transparency"]=0.999},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://15414904040",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.056,0.056,0.056),["TextureId"]="rbxassetid://15414905407",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}}}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["UFOKnife"] = {["ModelId"]="77607127867154",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["DoubleSided"]=false,["Material"]=Enum.Material.Plastic,["MeshId"]="rbxassetid://86649405964534",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.93289,3.79124,1.0541),["TextureID"]="rbxassetid://94763497877100",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["UFOKnifeChroma"] = {["ModelId"]="77607127867154",["Type"]="Knife",["Chroma"]=true,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Glass,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.933,3.791,1.054),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://86649405964534",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.07697,0.07697,0.07697),["TextureId"]="rbxassetid://94763497877100",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,0,0),["Face"]=Enum.NormalId.Left,["Texture"]="rbxassetid://138018131999412",["Transparency"]=0,["ZIndex"]=0},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["VampireAxe"] = {["ModelId"]="130837676383567",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["DoubleSided"]=false,["Material"]=Enum.Material.Slate,["MeshId"]="rbxassetid://92263601594064",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.31198,3.62749,1.92278),["TextureID"]="rbxassetid://73008954478338",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["VampireGun"] = {["ModelId"]="90274872705656",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.0482537655304126,0.04825445687384121,0.048254200000000004),["HeldGripSize"]=Vector3.new(0.42254,1.29266,2.41271),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="MeshPart",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["DoubleSided"]=false,["Material"]=Enum.Material.Slate,["MeshId"]="rbxassetid://126591885289479",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.42254,1.29266,2.41271),["TextureID"]="rbxassetid://104946799389637",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.20001,0.08992,1,0,0,0,0.64276,0.76607,0,-0.76607,0.64276)},["Children"]={}}}}},
    ["VampireGunChroma"] = {["ModelId"]="90274872705656",["Type"]="Gun",["Chroma"]=true,["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.05,0.05,0.05),["HeldGripSize"]=Vector3.new(0.422,1.292,2.412),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.422,1.292,2.412),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://126591885289479",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.05,0.05,0.05),["TextureId"]="rbxassetid://104946799389637",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,9,0),["Face"]=Enum.NormalId.Left,["Texture"]="rbxassetid://126923923696531",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.20001,0.08989,1,0,0,0,0.64276,0.76607,0,-0.76607,0.64276)},["Children"]={}}}}},
    ["VampiresEdge"] = {["ModelId"]="5873256998",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["DoubleSided"]=false,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://5841895234",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.39547,3.35145,1.01441),["TextureID"]="http://www.roblox.com/asset/?id=5842343736",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Virtual"] = {["ModelId"]="386276987",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,3,0.8),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=130101214",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.6,0.6,0.7),["TextureId"]="https://www.roblox.com/asset/?id=386250868",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Watergun"] = {["ModelId"]="18351388416",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.03947,0.03947,0.03947),["HeldGripSize"]=Vector3.new(0.448,1.365,2),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.448,1.365,2),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://18280999342",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.03947,0.03947,0.03947),["TextureId"]="rbxassetid://18281003313",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.20001,0.08992,1,0,0,0,0.64276,0.76607,0,-0.76607,0.64276)},["Children"]={}}}}},
    ["WatergunChroma"] = {["ModelId"]="18351401528",["Type"]="Gun",["Chroma"]=true,["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.03947,0.03947,0.03947),["HeldGripSize"]=Vector3.new(0.448,1.365,2),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="Part",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.448,1.365,2),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://18280999342",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.03947,0.03947,0.03947),["TextureId"]="rbxassetid://18281003313",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Decal",["Name"]="Chroma",["Props"]={["Color3"]=Color3.fromRGB(255,10,0),["Face"]=Enum.NormalId.Left,["Texture"]="rbxassetid://18335602807",["Transparency"]=0,["ZIndex"]=1},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.20004,0.0899,1,0,0,0,0.64276,0.76607,0,-0.76607,0.64276)},["Children"]={}}}}},
    ["Waves_K"] = {["ModelId"]="13945892398",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["DoubleSided"]=false,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://13916938702",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.30452,3.96204,1.26561),["TextureID"]="rbxassetid://13916939964",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["WintersEdge"] = {["ModelId"]="1268708987",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(4,175,236),["Material"]=Enum.Material.Plastic,["Reflectance"]=0.4,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.66,3,0.38),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset/?id=93108071",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.45,0.45,0.45),["TextureId"]="http://www.roblox.com/asset/?id=93112631",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(-0.05109,0.08594,-0.00051,-0.03483,-0.00184,-0.99939,0.03474,0.99939,-0.00305,0.99879,-0.03482,-0.03474)},["Children"]={}}}}},
    ["WraithGun"] = {["ModelId"]="75233248021696",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.0443864175623734,0.04438604951015915,0.0443862),["HeldGripSize"]=Vector3.new(0.45523,1.37271,2.21931),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="MeshPart",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["DoubleSided"]=false,["Material"]=Enum.Material.Slate,["MeshId"]="rbxassetid://79527507796407",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.45523,1.37271,2.21931),["TextureID"]="rbxassetid://80102752403085",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.19998,0.0899,1,0,0,0,0.64276,0.76607,0,-0.76607,0.64276)},["Children"]={}}}}},
    ["WraithKnife"] = {["ModelId"]="107190526940939",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["DoubleSided"]=false,["Material"]=Enum.Material.Slate,["MeshId"]="rbxassetid://112444333460928",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.22556,3.56844,0.95248),["TextureID"]="rbxassetid://131787177447081",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["XenoGun"] = {["ModelId"]="79722325448464",["Type"]="Gun",["Chroma"]=false,["HeldGrip"]=CFrame.new(0,-0.35,0.7,1,0,0,0,1,0,0,0,1),["HeldGripCalibrated"]=true,["HeldGripScale"]=Vector3.new(0.05334999939462598,0.053350279442404204,0.0533504),["HeldGripSize"]=Vector3.new(0.28155,1.31834,2.66752),["HeldGripOffset"]=Vector3.new(0,0,0),["Model"]={["Class"]="MeshPart",["Name"]="GunDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(143,34,34),["DoubleSided"]=true,["Material"]=Enum.Material.Brick,["MeshId"]="rbxassetid://96867436912658",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.28155,1.31834,2.66752),["TextureID"]="rbxassetid://103568875118220",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,-0.19998,0.0899,1,0,0,0,0.64276,0.76607,0,-0.76607,0.64276)},["Children"]={}}}}},
    ["XenoKnife"] = {["ModelId"]="100576599313371",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["DoubleSided"]=false,["Material"]=Enum.Material.Plastic,["MeshId"]="rbxassetid://136619680236977",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.20411,3.91908,0.74307),["TextureID"]="rbxassetid://113651973865393",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["Xmas"] = {["ModelId"]="473572568",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(17,17,17),["Material"]=Enum.Material.DiamondPlate,["Reflectance"]=0.01,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.4,3,0.8),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="rbxassetid://187852667",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.6,0.6,0.6),["TextureId"]="rbxassetid://187852629",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="CustomAttachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,0.99799,-0.06327,-0.00357,0.00363,0.00083,0.99999,-0.06326,-0.998,0.00106)},["Children"]={}}}}},
    ["YellowSeer"] = {["ModelId"]="3184124768",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="Part",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["Material"]=Enum.Material.Plastic,["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Shape"]=Enum.PartType.Block,["Size"]=Vector3.new(0.5,3.1,1),["Transparency"]=0},["Children"]={{["Class"]="SpecialMesh",["Name"]="Mesh",["Props"]={["MeshId"]="http://www.roblox.com/asset?id=156092238",["MeshType"]=Enum.MeshType.FileMesh,["Offset"]=Vector3.new(0,0,0),["Scale"]=Vector3.new(0.7,0.91,1),["TextureId"]="rbxassetid://3184063623",["VertexColor"]=Vector3.new(1,1,1)},["Children"]={}},{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
    ["ZombieBat"] = {["ModelId"]="11229814357",["Type"]="Knife",["Chroma"]=false,["Model"]={["Class"]="MeshPart",["Name"]="KnifeDisplay",["Props"]={["CastShadow"]=true,["Color"]=Color3.fromRGB(163,162,165),["DoubleSided"]=false,["Material"]=Enum.Material.Plastic,["MeshId"]="rbxassetid://11182796403",["Reflectance"]=0,["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1),["Size"]=Vector3.new(0.78195,3.70306,0.78373),["TextureID"]="rbxassetid://11192090515",["Transparency"]=0},["Children"]={{["Class"]="Attachment",["Name"]="Attachment",["Props"]={["RelCF"]=CFrame.new(0,0,0,1,0,0,0,1,0,0,0,1)},["Children"]={}}}}},
}
-- END VERIFIED WEAPON CATALOG
function Runtime.Visual.data(itemId)
    return (sync.Weapons and sync.Weapons[itemId]) or (sync.Item and sync.Item[itemId])
end
function Runtime.Visual.normalize(value)
    return tostring(value or ""):lower():gsub("[^%w]", "")
end
function Runtime.Visual.kind(data)
    if not data then return nil end
    local kind = data.ItemType or data.Type
    return kind == "Sword" and "Knife" or kind
end
-- Resolve legacy overrides once, using type, rarity and variant. An ambiguous
-- display name is never allowed to select another item's mesh or weapon slot.
function Runtime.Visual.buildEntries()
    local result = {}
    for key, entry in pairs(WeaponVisuals) do
        local direct = Runtime.Visual.data(key)
        local candidates = {}
        local variant = Runtime.Visual.normalize(key):find("chroma", 1, true) ~= nil
        if direct and Runtime.Visual.kind(direct) == entry.Type then
            table.insert(candidates, key)
        else
            for itemId, data in pairs(sync.Weapons or {}) do
                local name = Runtime.Visual.normalize(data.ItemName or data.Name)
                local normalizedKey = Runtime.Visual.normalize(key)
                local matchesName = normalizedKey == name
                    or (variant and (normalizedKey == "chroma" .. name or normalizedKey == name .. "chroma"))
                if Runtime.Visual.kind(data) == entry.Type
                    and (data.Chroma == true) == variant
                    and (data.Rarity == "Godly" or data.Rarity == "Ancient")
                    and (matchesName or Runtime.Visual.normalize(itemId) == normalizedKey) then
                    table.insert(candidates, itemId)
                end
            end
        end
        if #candidates == 1 then
            local id = candidates[1]
            local data = Runtime.Visual.data(id)
            local copy = table.clone(entry)
            copy.Type = Runtime.Visual.kind(data)
            copy.Chroma = data.Chroma == true
            local definition = Runtime.Visual.Catalog[id]
            copy.HeldGrip = copy.HeldGrip or (definition and definition.HeldGrip)
            copy.HeldGripScale = definition and definition.HeldGripScale
            copy.HeldGripSize = definition and definition.HeldGripSize
            copy.HeldGripOffset = definition and definition.HeldGripOffset
            result[id] = copy
        end
    end
    Runtime.Visual.Entries = result
    return result
end
Runtime.Visual.buildEntries()

function Runtime.Visual.report(itemId, message)
    if Runtime.Visual.Status[itemId] == message then return end
    Runtime.Visual.Status[itemId] = message
    if message then warn("[Carti Hub] " .. tostring(itemId) .. ": " .. message) end
    if Runtime.Visual.StatusLabel and Runtime.Visual.StatusLabel.Parent then
        Runtime.Visual.StatusLabel.Text = message and (tostring(itemId) .. ": " .. message) or ""
    end
end
function Runtime.Visual.sanitize(root)
    for _, descendant in ipairs(root:GetDescendants()) do
        if descendant:IsA("LuaSourceContainer") or descendant:IsA("JointInstance")
            or descendant:IsA("Constraint") or descendant:IsA("Sound")
            or descendant:IsA("ClickDetector") or descendant:IsA("ProximityPrompt") then
            descendant:Destroy()
        end
    end
    for _, part in ipairs({root, table.unpack(root:GetDescendants())}) do
        -- Captured models carry CollectionService tags. Leaving ChromaDecal
        -- on a proxy enrolls it in MM2's animator as well as ours, causing
        -- competing color/texture writes. Keep the visual intent locally.
        if part:IsA("Decal") and part:HasTag("ChromaDecal") then
            part:SetAttribute("CartiHubChromaDecal", true)
        elseif (part:IsA("BasePart") and part:HasTag("ChromaPart"))
            or (part:IsA("Fire") and part:HasTag("ChromaFire")) then
            part:SetAttribute("CartiHubChromaColor", true)
        end
        for _, tag in ipairs(part:GetTags()) do part:RemoveTag(tag) end
        if part:IsA("BasePart") then
            part.Anchored = false
            part.CanCollide = false
            part.CanTouch = false
            part.CanQuery = false
            part.Massless = true
        end
    end
    return root
end
function Runtime.Visual.assetPart(root)
    if root:IsA("BasePart") then return root end
    local handle = root:FindFirstChild("Handle", true)
    if handle and handle:IsA("BasePart") then return handle end
    if root:IsA("Model") and root.PrimaryPart then return root.PrimaryPart end
    return root:FindFirstChildWhichIsA("BasePart", true)
end
function Runtime.Visual.captureModel(root)
    local part = Runtime.Visual.assetPart(root)
    if not part then return nil end
    local ok, clone = pcall(function() return part:Clone() end)
    if not ok or not clone then return nil end
    if root:IsA("Tool") then clone:SetAttribute("CartiHubHeldGrip", root.Grip) end
    return Runtime.Visual.sanitize(clone)
end
function Runtime.Visual.findReplicatedModel(itemId)
    -- Only explicit canonical IDs qualify. Do not borrow another player's
    -- display by username or by a shared item display name.
    local data = Runtime.Visual.data(itemId)
    for _, root in ipairs({ReplicatedStorage, localPlayer:FindFirstChild("Backpack")}) do
        if root then
            for _, obj in ipairs(root:GetDescendants()) do
                if (obj:IsA("Model") or obj:IsA("Tool") or obj:IsA("BasePart"))
                    and (obj:GetAttribute("ItemID") == itemId or obj.Name == itemId) then
                    local model = Runtime.Visual.captureModel(obj)
                    if model then return model end
                end
            end
        end
    end
    for _, player in ipairs(Players:GetPlayers()) do
        local kind = Runtime.Visual.kind(data)
        if player ~= localPlayer and kind and player:GetAttribute("Equipped" .. kind) == itemId then
            local character = player.Character
            local ref = character and character:FindFirstChild("DisplayRef" .. Runtime.Visual.kind(data))
            if ref and ref:IsA("ObjectValue") and ref.Value then
                local model = Runtime.Visual.captureModel(ref.Value)
                if model then return model end
            end
        end
    end
    return nil
end
function Runtime.Visual.buildCatalogModel(itemId)
    local definition = Runtime.Visual.Catalog[itemId]
    local data = Runtime.Visual.data(itemId)
    if not definition or not data then return nil end
    if definition.Type ~= Runtime.Visual.kind(data)
        or definition.Chroma ~= (data.Chroma == true)
        or definition.ModelId ~= tostring(data.ItemID) then
        return nil, "Stored model metadata no longer matches this weapon."
    end
    local created = {}
    Runtime.Visual.Builds[created] = true
    local function build(node, parent)
        local object
        if node.Class == "MeshPart" then
            object = game:GetService("AssetService"):CreateMeshPartAsync(
                Content.fromUri(node.Props.MeshId), {CollisionFidelity = Enum.CollisionFidelity.Box})
        else
            object = Instance.new(node.Class)
        end
        assert(object, "Unable to create " .. node.Class)
        table.insert(created, object)
        if not Runtime.Active then error("Hub closed while loading model.") end
        object.Name = node.Name
        for property, value in pairs(node.Props) do
            if property == "RelCF" then
                if object:IsA("Attachment") or object:IsA("BasePart") then object.CFrame = value end
            elseif not (node.Class == "MeshPart" and property == "MeshId") then
                object[property] = value
            end
        end
        for name, value in pairs(node.Attributes or {}) do
            if name == "CartiHubChromaMesh" and type(value) == "boolean" then object:SetAttribute(name,value) end
        end
        object.Parent = parent
        for _, child in ipairs(node.Children or {}) do build(child, object) end
        return object
    end
    local ok, result = pcall(build, definition.Model, nil)
    Runtime.Visual.Builds[created] = nil
    if not ok then
        for _, object in ipairs(created) do object:Destroy() end
        return nil, tostring(result)
    end
    return Runtime.Visual.sanitize(result)
end
function Runtime.Visual.loadModel(itemId)
    if Runtime.Visual.Loading[itemId] or os.clock() < (Runtime.Visual.RetryAt[itemId] or 0) then return end
    Runtime.Visual.Loading[itemId] = true
    Runtime.Visual.report(itemId, "Loading weapon visual...")
    task.spawn(function()
        local data = Runtime.Visual.data(itemId)
        local model = Runtime.Visual.findReplicatedModel(itemId)
        if not model then model = Runtime.Visual.buildCatalogModel(itemId) end
        if not model and data and data.ItemID then
            local ok, objects = pcall(function()
                return game:GetObjects("rbxassetid://" .. tostring(data.ItemID))
            end)
            if ok and type(objects) == "table" then
                for _, obj in ipairs(objects) do
                    if not model then model = Runtime.Visual.captureModel(obj) end
                    obj:Destroy()
                end
            end
        end
        if not Runtime.Active then if model then model:Destroy() end; return end
        if model then
            local loadingParts = {model}
            Runtime.Visual.Builds[loadingParts] = true
            local unavailable = false
            local ok = pcall(function()
                game:GetService("ContentProvider"):PreloadAsync({model}, function(_, status)
                    if status ~= Enum.AssetFetchStatus.Success then unavailable = true end
                end)
            end)
            Runtime.Visual.Builds[loadingParts] = nil
            if not ok or unavailable or not Runtime.Active then model:Destroy(); model = nil end
        end
        if not Runtime.Active then return end
        Runtime.Visual.Loading[itemId] = nil
        if model then
            Runtime.Visual.Models[itemId] = model
            Runtime.Visual.report(itemId, nil)
        else
            Runtime.Visual.RetryAt[itemId] = os.clock() + 30
            Runtime.Visual.report(itemId, "Visual unavailable; original appearance restored.")
        end
    end)
end
function Runtime.Visual.resolve(itemId)
    local data = Runtime.Visual.data(itemId)
    if not data then return nil, "Unknown weapon ID." end
    local kind = Runtime.Visual.kind(data)
    if kind ~= "Knife" and kind ~= "Gun" then return nil, "Not a weapon." end
    local entry = Runtime.Visual.Entries[itemId]
    if entry then return entry end
    local source = Runtime.Visual.SourceOverrides[itemId] or Runtime.Visual.Models[itemId]
    if source then
        local definition = Runtime.Visual.Catalog[itemId]
        Runtime.Visual.Entries[itemId] = {Type = kind, Template = source, Chroma = data.Chroma == true,
            HeldGrip = source:GetAttribute("CartiHubHeldGrip") or (definition and definition.HeldGrip),
            HeldGripScale = definition and definition.HeldGripScale,
            HeldGripSize = definition and definition.HeldGripSize,
            HeldGripOffset = definition and definition.HeldGripOffset,
            ChromaRoot = itemId == "TreeKnife2023Chroma",
            -- Its actual game display uses KnifeBelt, even when the original
            -- locally owned knife still has a KnifeBack display constraint.
            Placement = definition and definition.Placement
                or (itemId == "IcecreamChroma" and "WaistLeft" or nil)}
        return Runtime.Visual.Entries[itemId]
    end
    -- Default equipment restores the untouched original model.
    if itemId == "DefaultKnife" or itemId == "DefaultGun" then return {Type = kind, Restore = true} end
    Runtime.Visual.loadModel(itemId)
    return nil, Runtime.Visual.Status[itemId] or "Visual unavailable; original appearance restored."
end
function Runtime.Visual.visualChild(instance)
    return instance:IsA("DataModelMesh") or instance:IsA("SurfaceAppearance")
        or instance:IsA("Decal") or instance:IsA("Texture") or instance:IsA("Attachment")
        or instance:IsA("ParticleEmitter") or instance:IsA("Trail") or instance:IsA("Beam")
        or instance:IsA("Light") or instance:IsA("Folder") or instance:IsA("Model")
end
function Runtime.Visual.makeProxy(entry)
    local proxy
    if entry.Template then
        proxy = entry.Template:Clone()
    else
        proxy = Instance.new("Part")
        proxy.Size = Vector3.new(1, 1, 1)
        proxy.Color = entry.Color or Color3.new(1, 1, 1)
        proxy.Material = entry.Material or Enum.Material.Plastic
        proxy.Transparency = entry.Transparency or 0
        proxy.Reflectance = entry.Reflectance or 0
        local mesh = Instance.new("SpecialMesh")
        mesh.MeshType = Enum.MeshType.FileMesh
        mesh.MeshId = entry.MeshId or ""
        mesh.TextureId = entry.TextureId or ""
        mesh.Scale = entry.Scale or Vector3.new(1, 1, 1)
        mesh.Offset = entry.Offset or Vector3.new(0, 0, 0)
        mesh.VertexColor = entry.VertexColor or Vector3.new(1, 1, 1)
        mesh.Parent = proxy
        if entry.Chroma and entry.ChromaTexture and entry.ChromaTexture ~= "" then
            local decal = Instance.new("Decal")
            decal.Name = "Chroma"
            decal.Face = entry.ChromaFace or Enum.NormalId.Back
            decal.Texture = entry.ChromaTexture
            decal.Parent = proxy
        end
    end
    Runtime.Visual.sanitize(proxy)
    proxy.Name = "CartiHubWeaponVisual"
    proxy:SetAttribute("CartiHubVisual", true)
    if entry.ChromaRoot then proxy:SetAttribute("CartiHubChromaColor", true) end
    return proxy
end
function Runtime.Visual.captureOriginal(target)
    local result = { Hidden = {} }
    local candidates = {target}
    for _, child in ipairs(target:GetDescendants()) do table.insert(candidates, child) end
    for _, child in ipairs(candidates) do
        if child:IsA("BasePart") or child:IsA("Decal") then
            result.Hidden[child] = {Property = "Transparency", Value = child.Transparency}
        elseif child:IsA("ParticleEmitter") or child:IsA("Trail") or child:IsA("Beam") or child:IsA("Light") then
            result.Hidden[child] = {Property = "Enabled", Value = child.Enabled}
        end
    end
    return result
end
function Runtime.Visual.restore(target)
    local state = Runtime.Visual.States[target]
    if not state then return end
    Runtime.Visual.States[target] = nil
    for _, connection in ipairs(state.Connections or {}) do connection:Disconnect() end
    if state.Proxy then state.Proxy:Destroy() end
    for instance, property in pairs(state.Original.Hidden) do
        pcall(function() instance[property.Property] = property.Value end)
    end
end
function Runtime.Visual.placement(character, target, entry)
    -- Compute a cosmetic mount. Never retarget the game's RigidConstraint or
    -- edit its attachment: either endpoint may belong to the avatar's body.
    local targetAttachment = target:FindFirstChildOfClass("Attachment")
    local visualAttachment = targetAttachment and targetAttachment.CFrame or CFrame.new()
    if entry.Template then
        local sourceAttachment = entry.Template:FindFirstChild("CustomAttachment")
            or entry.Template:FindFirstChildOfClass("Attachment")
        if sourceAttachment then visualAttachment = sourceAttachment.CFrame end
    elseif entry.AttachmentPosition or entry.AttachmentOrientation then
        local position = entry.AttachmentPosition or visualAttachment.Position
        local rotation = visualAttachment.Rotation
        if entry.AttachmentOrientation then
            local angles = entry.AttachmentOrientation
            rotation = CFrame.fromOrientation(math.rad(angles.X), math.rad(angles.Y), math.rad(angles.Z))
        end
        visualAttachment = CFrame.new(position) * rotation
    end
    local locations = {Back = {"UpperTorso", "KnifeBack"}, WaistLeft = {"LowerTorso", "KnifeBelt"}, WaistRight = {"LowerTorso", "GunBelt"}}
    local location = character and locations[entry.Placement]
    local body = location and character:FindFirstChild(location[1])
    local bodyAttachment = body and body:FindFirstChild(location[2])
    if body and body:IsA("BasePart") and bodyAttachment and bodyAttachment:IsA("Attachment") then
        return body, bodyAttachment.CFrame * visualAttachment:Inverse()
    end
    -- The existing display already follows the correct body anchor. Correct
    -- only the proxy's local offset when using a different authored attachment.
    return target, (targetAttachment and targetAttachment.CFrame or CFrame.new()) * visualAttachment:Inverse()
end
-- BEGIN HELD WEAPON GRIPS
function Runtime.Visual.heldGrip(entry)
    local template = entry.Template
    local captured = template and template:GetAttribute('CartiHubHeldGrip')
    local attachment = template and template:FindFirstChild('RightGripAttachment')
    -- A captured Tool/hand attachment already describes this exact geometry.
    if attachment and attachment:IsA('Attachment') then return attachment.CFrame end
    if typeof(captured) == 'CFrame' then return captured end
    local grip = entry.HeldGrip
    if typeof(grip) == 'CFrame' then
        local scale, offset
        local mesh = template and template:FindFirstChildOfClass('SpecialMesh')
        if mesh then
            if entry.HeldGripScale then scale = mesh.Scale / entry.HeldGripScale end
            offset = mesh.Offset
        elseif template and template:IsA('MeshPart') then
            if entry.HeldGripSize then scale = template.Size / entry.HeldGripSize end
            offset = Vector3.zero
        elseif entry.Scale then
            if entry.HeldGripScale then scale = entry.Scale / entry.HeldGripScale end
            offset = entry.Offset or Vector3.zero
        end
        if scale then
            local position = (grip.Position - (entry.HeldGripOffset or Vector3.zero)) * scale
                + (offset or Vector3.zero)
            grip = CFrame.new(position) * grip.Rotation
        end
        return grip
    end
    if entry.Type ~= 'Gun' then return nil end
    -- Uncatalogued gun models still need their own hand frame; inheriting the
    -- current gameplay weapon's C1 can turn a horizontal mesh upright.
    local size = template and template.Size or Vector3.new(.4, 1.3, 2)
    if size.Y > size.Z and size.Y > size.X then
        return CFrame.new(0, -.7, -.3) * CFrame.Angles(math.pi / 2, 0, 0)
    elseif size.X > size.Z then
        return CFrame.new(0, -.35, 0) * CFrame.Angles(0, math.pi / 2, 0)
    end
    return CFrame.new(0, -.35, .7)
end
function Runtime.Visual.heldOffset(entry, target)
    -- Belt/back CustomAttachment never determines a hand grip. Read the actual
    -- native handle endpoint, and transform only the cosmetic proxy.
    local authoredGrip = Runtime.Visual.heldGrip(entry)
    if not authoredGrip then return CFrame.new() end
    local originalGrip = CFrame.new()
    local tool = target and target:FindFirstAncestorOfClass('Tool')
    if tool then
        originalGrip = tool.Grip
        local attachment = target:FindFirstChild('RightGripAttachment')
        if attachment and attachment:IsA('Attachment') then originalGrip = attachment.CFrame end
        local character = tool.Parent
        if character and character:IsA('Model') then
            for _, joint in ipairs(character:GetDescendants()) do
                if (joint:IsA('JointInstance') or joint:IsA('AnimationConstraint'))
                    and joint.Name == 'RightGrip' and joint.Part1 == target then
                    originalGrip = joint.C1
                    break
                elseif (joint:IsA('RigidConstraint') or joint:IsA('AnimationConstraint'))
                    and joint.Attachment0 and joint.Attachment1 then
                    local a, b = joint.Attachment0, joint.Attachment1
                    if a.Parent == target and b:IsDescendantOf(character) and not b:IsDescendantOf(tool) then
                        originalGrip = a.CFrame
                        break
                    elseif b.Parent == target and a:IsDescendantOf(character) and not a:IsDescendantOf(tool) then
                        originalGrip = b.CFrame
                        break
                    end
                end
            end
        end
    end
    return originalGrip * authoredGrip:Inverse()
end
-- END HELD WEAPON GRIPS
function Runtime.Visual.fingerprint(root)
    local parts = {}
    local instances = {root}
    for _, child in ipairs(root:GetDescendants()) do table.insert(instances, child) end
    for _, obj in ipairs(instances) do
        local values = {obj.ClassName, obj.Name}
        if obj:IsA("BasePart") then
            table.insert(values, tostring(obj.Size))
            table.insert(values, obj:GetAttribute("CartiHubChromaColor") and "animated-color" or tostring(obj.Color))
            table.insert(values, tostring(obj.Material)); table.insert(values, tostring(obj.Transparency))
            table.insert(values, tostring(obj.Reflectance)); table.insert(values, tostring(obj.CanCollide))
            table.insert(values, tostring(obj.CanTouch)); table.insert(values, tostring(obj.CanQuery))
            table.insert(values, tostring(obj.Anchored)); table.insert(values, tostring(obj.Massless))
            if obj:IsA("MeshPart") then table.insert(values, obj.MeshId); table.insert(values, obj.TextureID) end
        elseif obj:IsA("SpecialMesh") then
            table.insert(values, obj.MeshId); table.insert(values, obj.TextureId)
            table.insert(values, tostring(obj.Scale)); table.insert(values, tostring(obj.Offset))
            table.insert(values, obj:GetAttribute("CartiHubChromaMesh") and "animated-vertex-color" or tostring(obj.VertexColor))
        elseif obj:IsA("Decal") then
            table.insert(values, obj.Texture); table.insert(values, tostring(obj.Face)); table.insert(values, tostring(obj.Transparency))
        elseif obj:IsA("SurfaceAppearance") then
            table.insert(values, obj.ColorMap); table.insert(values, obj.MetalnessMap)
            table.insert(values, obj.NormalMap); table.insert(values, obj.RoughnessMap)
        end
        table.insert(parts, table.concat(values, ":"))
    end
    table.sort(parts)
    return table.concat(parts, "|")
end
function Runtime.Visual.setVisible(state, visible)
    if state.Visible == visible then return end
    state.Visible = visible
    state.Appearance = state.Appearance or Runtime.Visual.captureOriginal(state.Proxy).Hidden
    for object, property in pairs(state.Appearance) do
        if object.Parent then
            object[property.Property] = visible and property.Value
                or (property.Property == "Transparency" and 1 or false)
        end
    end
    state.Fingerprint = Runtime.Visual.fingerprint(state.Proxy)
end
function Runtime.Visual.animateChroma(proxy, hue)
    local color = Color3.fromHSV(hue % 1, 1, 1)
    if proxy:GetAttribute("CartiHubChromaColor") then proxy.Color = color end
    for _, child in ipairs(proxy:GetDescendants()) do
        if child:IsA("Decal") and (child.Name == "Chroma" or child:GetAttribute("CartiHubChromaDecal")) then
            child.Color3 = color
        elseif child:GetAttribute("CartiHubChromaColor") and (child:IsA("BasePart") or child:IsA("Fire")) then
            child.Color = color
        elseif child:IsA("SpecialMesh") and child:GetAttribute("CartiHubChromaMesh") then
            local tint=Color3.fromHSV(hue % 1,.78,1)
            child.VertexColor=Vector3.new(.62+tint.R*.38,.62+tint.G*.38,.62+tint.B*.38)
        end
    end
end
function Runtime.Visual.removeClonedProxies(handle)
    local scripts = localPlayer:FindFirstChild("PlayerScripts")
    local glowScript = scripts and scripts:FindFirstChild("ToolHandleVisuals")
    for _, root in pairs({workspace, glowScript}) do
        for _, clone in ipairs(root:GetChildren()) do
            local constraint = clone:IsA("BasePart") and clone:FindFirstChild("VisualConstraint")
            if constraint and constraint:IsA("RigidConstraint") then
                local a, b = constraint.Attachment0, constraint.Attachment1
                if (a and a.Parent == handle) or (b and b.Parent == handle) then
                    for _, child in ipairs(clone:GetChildren()) do
                        if child:GetAttribute("CartiHubVisual") then child:Destroy() end
                    end
                end
            end
        end
    end
end
function Runtime.Visual.applyTarget(target, itemId, entry, character, held)
    if not target or not target:IsA("BasePart") then return false end
    if not entry or entry.Restore then Runtime.Visual.restore(target); return entry ~= nil end
    local mountPart, mountOffset = target, CFrame.new()
    if held then
        mountOffset = Runtime.Visual.heldOffset(entry, target)
    else
        mountPart, mountOffset = Runtime.Visual.placement(character, target, entry)
    end
    local state = Runtime.Visual.States[target]
    if state and (state.ItemId ~= itemId or state.Entry ~= entry
        or not state.Proxy.Parent or not state.Weld.Parent
        or state.Weld.Part0 ~= mountPart or state.Weld.Part1 ~= state.Proxy
        or state.MountOffset ~= mountOffset
        or Runtime.Visual.fingerprint(state.Proxy) ~= state.Fingerprint) then
        Runtime.Visual.restore(target)
        state = nil
    end
    if not state then
        state = { ItemId = itemId, Entry = entry, Original = Runtime.Visual.captureOriginal(target), Connections = {} }
        local proxy = Runtime.Visual.makeProxy(entry)
        -- MM2's GlowTool handler clones the original handle. Its clone must
        -- not inherit another copy of our cosmetic geometry or body welds.
        proxy.Archivable = false
        state.Proxy = proxy
        local mountedCFrame = mountPart.CFrame * mountOffset
        local delta = mountedCFrame * proxy.CFrame:Inverse()
        for _, child in ipairs(proxy:GetDescendants()) do
            if child:IsA("BasePart") then child.CFrame = delta * child.CFrame end
        end
        proxy.CFrame = mountedCFrame
        proxy.Parent = target
        local weld = Instance.new("WeldConstraint")
        weld.Part0, weld.Part1 = mountPart, proxy
        weld.Parent = proxy
        state.Weld = weld
        state.MountOffset = mountOffset
        for _, child in ipairs(proxy:GetDescendants()) do
            if child:IsA("BasePart") then
                local childWeld = Instance.new("WeldConstraint")
                childWeld.Part0, childWeld.Part1 = proxy, child
                childWeld.Parent = child
            end
        end
        state.Fingerprint = Runtime.Visual.fingerprint(proxy)
        Runtime.Visual.States[target] = state
        if entry.Chroma then
            task.spawn(function()
                while Runtime.Active and Runtime.Visual.States[target] == state and proxy.Parent do
                    Runtime.Visual.animateChroma(proxy, os.clock() / 6)
                    task.wait(1 / 30)
                end
            end)
        end
    end
    for instance, property in pairs(state.Original.Hidden) do
        if instance.Parent then instance[property.Property] = property.Property == "Transparency" and 1 or false end
    end
    return true
end
function Runtime.Visual.apply(itemId, character, backpack)
    local data = Runtime.Visual.data(itemId)
    local kind = Runtime.Visual.kind(data)
    if kind ~= "Knife" and kind ~= "Gun" then return false, "Unknown weapon type." end
    character = character or localPlayer.Character
    if not character then return false, "Character is unavailable." end
    if Runtime.AvatarWeapons and Runtime.AvatarWeapons:IsChanging(character) then
        return false, 'Waiting for the avatar change to finish.'
    end
    local entry, reason = Runtime.Visual.resolve(itemId)
    local applied, targets = false, {}
    local heldTool = false
    for _, tool in ipairs(character:GetChildren()) do
        if tool:IsA("Tool") then
            local toolKind = tool:GetAttribute("ItemType") or tool:GetAttribute("WeaponType") or tool.Name
            if toolKind == kind or (kind == "Knife" and toolKind == "Sword") then heldTool = true; break end
        end
    end
    local ref = character:FindFirstChild("DisplayRef" .. kind)
    if ref and ref:IsA("ObjectValue") and ref.Value then
        targets[ref.Value] = true
        applied = Runtime.Visual.applyTarget(ref.Value, itemId, entry, character, false) or applied
        local state = Runtime.Visual.States[ref.Value]
        if state then Runtime.Visual.setVisible(state, not heldTool) end
    end
    for _, root in ipairs({character, backpack or localPlayer:FindFirstChild("Backpack")}) do
        if root then
            for _, tool in ipairs(root:GetChildren()) do
                if tool:IsA("Tool") then
                    local toolKind = tool:GetAttribute("ItemType") or tool:GetAttribute("WeaponType")
                    if not toolKind and (tool.Name == "Knife" or tool.Name == "Gun") then toolKind = tool.Name end
                    local handle = tool:FindFirstChild("Handle")
                    if toolKind == kind and handle and handle:IsA("BasePart") then
                        Runtime.Visual.removeClonedProxies(handle)
                        targets[handle] = true
                        applied = Runtime.Visual.applyTarget(handle, itemId, entry, character, true) or applied
                    end
                end
            end
        end
    end
    for target, state in pairs(Runtime.Visual.States) do
        local old = Runtime.Visual.data(state.ItemId)
        if (not target.Parent) or (Runtime.Visual.kind(old) == kind and not targets[target]) then Runtime.Visual.restore(target) end
    end
    if not entry then Runtime.Visual.report(itemId, reason); return false, reason end
    if applied then Runtime.Visual.report(itemId, nil) end
    return applied, applied and nil or "Waiting for a weapon display or tool."
end
-- BEGIN NPC WEAPONS
-- Cosmetic equipment owned by each scene actor, never the player's inventory.
do
    local visual = Runtime.Visual
    local random = Random.new()
    local starterPairs = {{"Seer","Luger"},{"Candy","Sugar"},{"Ghostblade","Laser"},{"Gemstone","Shark"}}
    local function item(value, kind)
        value = tostring(value or ""):match("^%s*(.-)%s*$")
        local data = visual.data(value)
        if data and visual.kind(data) == kind then return value end
        local normalized, match = visual.normalize(value), nil
        for id, entry in pairs(sync.Weapons or {}) do
            if visual.kind(entry) == kind and visual.normalize(entry.ItemName) == normalized and not entry.Chroma then
                if match then return nil end
                match = id
            end
        end
        return match
    end
    function Runtime.configureNPCWeapons(npc)
        local function changed() if npc.Changed then npc.Changed() end end
        local function clearSlot(slot)
            if slot and slot.Proxy then slot.Proxy:Destroy() end
        end
        function npc:ClearLoadout(record)
            if not record or not record.Weapons then return end
            for _,slot in pairs(record.Weapons.Slots) do clearSlot(slot) end
            record.Weapons = nil
            if record.Tracks and record.Tracks.ToolHold then record.Tracks.ToolHold:Stop(.15) end
        end
        function npc:GetLoadout(record)
            if not record or not record.Weapons then return nil end
            return {Knife=record.Weapons.Knife, Gun=record.Weapons.Gun,
                Equipped=record.Weapons.Equipped, AutoWeapons=record.AutoWeapons}
        end
        function npc:SetLoadout(record, knife, gun)
            if not record or record.Disposed or self.Records[record.Id] ~= record then return false,"Select a loaded NPC first." end
            local knifeId, gunId = item(knife,"Knife"), item(gun,"Gun")
            if not knifeId or not gunId then return false,"Enter a valid knife and gun ID, or an unambiguous item name." end
            local previous = record.Weapons
            self:ClearLoadout(record)
            record.Weapons = {Knife=knifeId,Gun=gunId,Slots={},Equipped=previous and previous.Equipped or "Holstered"}
            record.AutoWeapons = record.AutoWeapons ~= false
            record.WeaponNext = os.clock()+random:NextNumber(12,28)
            changed(); return true
        end
        function npc:EquipWeapon(record, kind)
            if not record or record.Disposed or not record.Weapons or (kind~="Knife" and kind~="Gun" and kind~="Holstered") then return false end
            record.Weapons.Equipped=kind;record.WeaponNext=os.clock()+random:NextNumber(14,32)
            changed();return true
        end
        function npc:SetAutoWeapons(record, enabled)
            if not record or record.Disposed or not record.Weapons then return false end
            record.AutoWeapons=enabled==true;record.WeaponNext=os.clock()+random:NextNumber(12,28)
            changed();return true
        end
        function npc:ApplyLoadout(record)
            local pair = starterPairs[(record.Id-1)%#starterPairs+1]
            self:SetLoadout(record,pair[1],pair[2])
        end
        local function entryFor(id)
            local entry = visual.resolve(id)
            if entry and entry.Restore then
                local template = visual.Models[id]
                if not template then visual.loadModel(id);return nil end
                return {Type=visual.kind(visual.data(id)),Template=template}
            end
            return entry
        end
        local function mount(record,kind,entry,held)
            if held then
                local hand=record.Model:FindFirstChild("RightHand")
                if not hand then return end
                local grip=hand:FindFirstChild("RightGripAttachment")
                -- The actor's own handle frame uses Roblox's neutral Tool grip.
                local handleOffset=grip and grip.CFrame
                    or CFrame.new(0,-hand.Size.Y*.5,0)*CFrame.Angles(-math.pi/2,0,0)
                return hand,handleOffset*visual.heldOffset(entry)
            end
            local location=entry.Placement or (kind=="Knife" and "WaistLeft" or "WaistRight")
            local body=record.Model:FindFirstChild(location=="Back" and "UpperTorso" or "LowerTorso")
            if not body then return end
            local side=kind=="Knife" and -1 or 1
            local anchor=location=="Back" and CFrame.new(0,0,body.Size.Z*.5+.15)
                or CFrame.new(side*(body.Size.X*.5+.12),-body.Size.Y*.2,body.Size.Z*.3)
            local attachment=entry.Template and (entry.Template:FindFirstChild("CustomAttachment") or entry.Template:FindFirstChildOfClass("Attachment"))
            local authored=attachment and attachment.CFrame or CFrame.new()
            if not attachment and (entry.AttachmentPosition or entry.AttachmentOrientation) then
                local angles=entry.AttachmentOrientation or Vector3.zero
                authored=CFrame.new(entry.AttachmentPosition or Vector3.zero)*CFrame.fromOrientation(math.rad(angles.X),math.rad(angles.Y),math.rad(angles.Z))
            end
            return body,anchor*authored:Inverse()
        end
        local function createSlot(record, kind, entry)
            local proxy=visual.makeProxy(entry)
            proxy.Name="NPC"..kind;proxy.Archivable=false
            local initial=proxy.CFrame
            local relative={}
            for _,part in ipairs(proxy:GetDescendants()) do
                if part:IsA("BasePart") then relative[part]=initial:ToObjectSpace(part.CFrame) end
            end
            local part,offset=mount(record,kind,entry,false)
            if not part then proxy:Destroy();return nil end
            proxy.CFrame=part.CFrame*offset
            proxy.Parent=record.Model
            for child,cf in pairs(relative) do
                child.CFrame=proxy.CFrame*cf
                local weld=Instance.new("Weld",child);weld.Part0,weld.Part1,weld.C0=proxy,child,cf
            end
            local weld=Instance.new("Weld",proxy)
            weld.Part0,weld.Part1,weld.C0=part,proxy,offset
            return {Proxy=proxy,Weld=weld,Entry=entry,Held=false}
        end
        function npc:StepWeapons(now)
            for _,record in pairs(self.Records) do
                local weapons=record.Weapons
                if not record.Disposed and weapons then
                    local gesturing=record.Gesture and now<(record.GestureUntil or 0)
                    if record.AutoWeapons and now>=(record.WeaponNext or math.huge) and not self.Paused and not record.Paused
                        and not gesturing and now>(record.PauseUntil or 0) then
                        local nextSlot=({"Holstered","Holstered","Knife","Gun"})[random:NextInteger(1,4)]
                        local gunSlot=weapons.Slots.Gun
                        if nextSlot=="Gun" and (not gunSlot or not visual.heldGrip(gunSlot.Entry)) then nextSlot="Holstered" end
                        self:EquipWeapon(record,nextSlot)
                    end
                    local holding=false
                    for _,kind in ipairs({"Knife","Gun"}) do
                        local slot=weapons.Slots[kind]
                        if not slot then
                            local entry=entryFor(weapons[kind])
                            if entry then slot=createSlot(record,kind,entry);weapons.Slots[kind]=slot end
                        end
                        if slot then
                            local held=weapons.Equipped==kind
                            holding=holding or held
                            if slot.Held~=held then
                                local part,offset=mount(record,kind,slot.Entry,held)
                                if part then slot.Weld.Part0,slot.Weld.C0=part,offset;slot.Held=held end
                            end
                            if slot.Entry.Chroma then visual.animateChroma(slot.Proxy,now/6) end
                        end
                    end
                    if holding and record.AnimationsEnabled~=false and not gesturing then
                        if not record.Tracks.ToolHold then
                            local animation=Instance.new("Animation");animation.AnimationId="rbxassetid://507768375"
                            local ok,track=pcall(function() return record.Animator:LoadAnimation(animation) end)
                            animation:Destroy()
                            if ok then track.Priority=Enum.AnimationPriority.Action;track.Looped=true;record.Tracks.ToolHold=track end
                        end
                        local track=record.Tracks.ToolHold
                        if track and not track.IsPlaying then track:Play(.2) end
                    elseif record.Tracks.ToolHold and record.Tracks.ToolHold.IsPlaying then record.Tracks.ToolHold:Stop(.2) end
                end
            end
        end
    end
    Runtime.configureNPCWeapons(Runtime.NPC)
    task.spawn(function()
        while Runtime.Active and Runtime.NPC.Active do Runtime.NPC:StepWeapons(os.clock());task.wait(1/20) end
    end)
end
-- END NPC WEAPONS

-- MM2's custom backpack copies TextureId only when a slot is created. Keep
-- the actual Tool and that cached slot in sync with the local skin selection.
do
    local Icons = {}
    Icons.__index = Icons
    function Icons.new()
        return setmetatable({Tools = {}, Slots = {}}, Icons)
    end
    function Icons.kind(tool)
        if not tool:IsA("Tool") then return nil end
        local kind = tool:GetAttribute("ItemType") or tool:GetAttribute("WeaponType")
        if not kind and (tool.Name == "Knife" or tool.Name == "Gun") then kind = tool.Name end
        return kind == "Sword" and "Knife" or kind
    end
    function Icons.image(itemId, kind)
        local data = type(itemId) == "string" and Runtime.Visual.data(itemId)
        if not data or Runtime.Visual.kind(data) ~= kind then return nil end
        local value = data.Image
        if type(value) == "number" and value > 0 then return "rbxassetid://" .. tostring(value) end
        if type(value) ~= "string" or not value:find("%S") then return nil end
        if value:match("^%d+$") then return "rbxassetid://" .. value end
        return value
    end
    function Icons:restoreTool(tool)
        local state = self.Tools[tool]
        if not state then return end
        pcall(function()
            if tool.TextureId == state.Applied then tool.TextureId = state.Original end
        end)
        self.Tools[tool] = nil
    end
    function Icons:restoreSlot(icon)
        local state = self.Slots[icon]
        if not state then return end
        pcall(function()
            if icon.Image == state.Applied then icon.Image = state.Original end
            if state.Label and state.Label.Text == "" then state.Label.Text = state.OriginalName end
        end)
        self.Slots[icon] = nil
    end
    function Icons:clear()
        for icon in pairs(self.Slots) do self:restoreSlot(icon) end
        for tool in pairs(self.Tools) do self:restoreTool(tool) end
    end
    function Icons:sync(character, backpack, playerGui, equipped)
        local records, seen, tagged = {}, {}, {}
        for _, root in pairs({character, backpack}) do
            for _, tool in ipairs(root:GetChildren()) do
                if tool:IsA("Tool") and not seen[tool] then
                    local state = self.Tools[tool]
                    if state and tool.TextureId ~= state.Applied then state.Original = tool.TextureId end
                    local kind = Icons.kind(tool)
                    local record = {Tool = tool, Texture = tool.TextureId, State = state}
                    if kind == "Knife" or kind == "Gun" then record.Image = Icons.image(equipped and equipped[kind], kind) end
                    records[#records + 1], seen[tool] = record, record
                    if tool:HasTag("Weapon") then tagged[#tagged + 1] = record end
                end
            end
        end
        local ui = playerGui and playerGui:FindFirstChild("BackpackUI")
        local frame = ui and ui:FindFirstChild("BackpackFrame")
        local activeSlots = {}
        for _, slot in ipairs(frame and frame:GetChildren() or {}) do
            local container = slot:FindFirstChild("Container")
            local icon = container and container:FindFirstChild("ToolIcon")
            local label = container and container:FindFirstChild("NameLabel")
            if slot:IsA("GuiObject") and icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
                local previous, record = self.Slots[icon], nil
                -- MM2 reserves slot 1 for a Tool tagged Weapon. Other slots
                -- are matched only when their existing image identifies one Tool.
                if slot.LayoutOrder == 1 and #tagged == 1 then
                    record = tagged[1]
                elseif previous and seen[previous.Tool] and icon.Image == previous.Applied then
                    record = seen[previous.Tool]
                else
                    local matches = 0
                    for _, candidate in ipairs(records) do
                        local state = candidate.State
                        local sameImage = icon.Image ~= "" and (icon.Image == candidate.Texture
                            or (state and (icon.Image == state.Original or icon.Image == state.Applied)))
                        local sameName = icon.Image == "" and candidate.Texture == ""
                            and label and label:IsA("TextLabel") and label.Text == candidate.Tool.Name
                        if sameImage or sameName then record, matches = candidate, matches + 1 end
                    end
                    if matches ~= 1 then record = nil end
                end
                if record and record.Image then
                    if previous and previous.Tool ~= record.Tool then self:restoreSlot(icon); previous = nil end
                    local state = previous or {Tool = record.Tool, Original = icon.Image,
                        Label = label and label:IsA("TextLabel") and label or nil,
                        OriginalName = label and label:IsA("TextLabel") and label.Text or ""}
                    if previous and icon.Image ~= state.Applied then state.Original = icon.Image end
                    if previous and state.Label and state.Label.Text ~= "" then state.OriginalName = state.Label.Text end
                    -- A slot created after the Tool changed already contains our
                    -- image. Its restoration must still use the game's texture.
                    local toolState = record.State
                    if not previous and toolState and icon.Image == toolState.Applied then
                        state.Original = toolState.Original
                        state.OriginalName = toolState.Original == "" and record.Tool.Name or ""
                    end
                    state.Applied = record.Image
                    if icon.Image ~= record.Image then icon.Image = record.Image end
                    if state.Label and state.Label.Text ~= "" then state.Label.Text = "" end
                    self.Slots[icon], activeSlots[icon] = state, true
                end
            end
        end
        for icon in pairs(self.Slots) do if not activeSlots[icon] then self:restoreSlot(icon) end end
        for _, record in ipairs(records) do
            if record.Image then
                local state = self.Tools[record.Tool] or {Original = record.Texture}
                state.Applied = record.Image
                if record.Tool.TextureId ~= record.Image then record.Tool.TextureId = record.Image end
                self.Tools[record.Tool] = state
            else
                self:restoreTool(record.Tool)
            end
        end
        for tool in pairs(self.Tools) do if not seen[tool] then self:restoreTool(tool) end end
    end
    Runtime.ToolIcons = Icons.new()
    Runtime.cleanup(function() Runtime.ToolIcons:clear() end)
end
local function syncEquippedToolIcons()
    Runtime.ToolIcons:sync(localPlayer.Character, localPlayer:FindFirstChild("Backpack"),
        localPlayer:FindFirstChild("PlayerGui"), profileData.Weapons and profileData.Weapons.Equipped)
end
local function applyWeaponVisual(itemId)
    syncEquippedToolIcons()
    return Runtime.Visual.apply(itemId)
end
local function getLocalEquippedWeaponIds()
    local result = {}
    for _, id in pairs(profileData.Weapons and profileData.Weapons.Equipped or {}) do
        if type(id) == "string" then table.insert(result, id) end
    end
    return result
end
local function applyEquippedWeaponVisuals()
    syncEquippedToolIcons()
    local success = true
    for _, itemId in ipairs(getLocalEquippedWeaponIds()) do
        local ok, applied, reason = pcall(Runtime.Visual.apply, itemId)
        if not ok or not applied then
            success = false
            if not ok then Runtime.Visual.report(itemId, tostring(applied))
            elseif reason and not reason:find("Waiting", 1, true) then Runtime.Visual.report(itemId, reason) end
        end
    end
    return success
end
Runtime.cleanup(function()
    for target in pairs(Runtime.Visual.States) do Runtime.Visual.restore(target) end
    for _, model in pairs(Runtime.Visual.Models) do model:Destroy() end
    for created in pairs(Runtime.Visual.Builds) do
        for _, object in ipairs(created) do object:Destroy() end
    end
    table.clear(Runtime.Visual.Builds)
end)
Runtime.connect(localPlayer.CharacterAdded, function(character)
    Runtime.connect(character.ChildAdded, function() task.defer(applyEquippedWeaponVisuals) end)
    task.defer(applyEquippedWeaponVisuals)
end)
if localPlayer.Character then Runtime.connect(localPlayer.Character.ChildAdded, function() task.defer(applyEquippedWeaponVisuals) end) end
local function watchWeaponBackpack(backpack)
    if backpack:IsA("Backpack") then
        Runtime.connect(backpack.ChildAdded, function() task.defer(applyEquippedWeaponVisuals) end)
        task.defer(applyEquippedWeaponVisuals)
    end
end
Runtime.connect(localPlayer.ChildAdded, watchWeaponBackpack)
if localPlayer:FindFirstChild("Backpack") then watchWeaponBackpack(localPlayer.Backpack) end
task.spawn(function()
    while Runtime.Active do
        applyEquippedWeaponVisuals()
        task.wait(0.35)
    end
end)
-- END CARTI VISUAL RENDERER

-- BEGIN AVATAR WEAPON BINDINGS
function Runtime.createAvatarWeaponController(options)
    options = options or {}
    local controller = {Active = true, Pending = {}, Generation = 0, Latest = {}}
    local anchorNames = {KnifeBelt = true, KnifeBack = true, GunBelt = true}
    local function current(character)
        return character == (options.GetCharacter and options.GetCharacter() or localPlayer.Character)
    end
    local function describe(attachment, character)
        local part = attachment and attachment.Parent
        if not part or not part:IsA('BasePart') or part.Parent ~= character or not anchorNames[attachment.Name] then return end
        return {Part = part.Name, Name = attachment.Name, CFrame = attachment.CFrame, Size = part.Size}
    end
    function controller:IsChanging(character) return self.Pending[character] ~= nil end
    function controller:IsCurrent(snapshot)
        return self.Active and current(snapshot.Character) and snapshot.Character.Parent ~= nil
            and self.Latest[snapshot.Character] == snapshot.Generation
    end
    function controller:Begin(character, backpack)
        if not self.Active or not current(character) then return nil, 'CHARACTER CHANGED' end
        if self.Pending[character] then return nil, 'AVATAR CHANGE IN PROGRESS' end
        local humanoid = character:FindFirstChildOfClass('Humanoid')
        if not humanoid then return nil, 'NO HUMANOID' end
        self.Generation += 1
        local snapshot = {Character = character, Backpack = backpack, Humanoid = humanoid, Generation = self.Generation,
            Anchors = {}, Displays = {}, Held = {}}
        for _, part in ipairs(character:GetChildren()) do
            if part:IsA('BasePart') then
                for _, attachment in ipairs(part:GetChildren()) do
                    if attachment:IsA('Attachment') and anchorNames[attachment.Name] then
                        table.insert(snapshot.Anchors, describe(attachment, character))
                    end
                end
            elseif part:IsA('Tool') then table.insert(snapshot.Held, part) end
        end
        for _, kind in ipairs({'Knife', 'Gun'}) do
            local ref = character:FindFirstChild('DisplayRef' .. kind)
            local display = ref and ref:IsA('ObjectValue') and ref.Value
            if display then
                local record = {Ref = ref, Target = display, Bindings = {}}
                for _, constraint in ipairs(display:GetDescendants()) do
                    if constraint:IsA('RigidConstraint') then
                        for _, property in ipairs({'Attachment0', 'Attachment1'}) do
                            local anchor = describe(constraint[property], character)
                            if anchor then table.insert(record.Bindings, {Constraint = constraint, Property = property, Anchor = anchor}) end
                        end
                    end
                end
                table.insert(snapshot.Displays, record)
            end
        end
        if #snapshot.Held > 0 and not backpack then return nil, 'BACKPACK NOT READY' end
        self.Pending[character], self.Latest[character] = snapshot, snapshot.Generation
        -- Proxies must not survive into body scaling/replacement. Their state may
        -- otherwise keep a weld to a deleted torso even though the Tool survives.
        if options.ClearVisuals then
            local ok = pcall(options.ClearVisuals, snapshot)
            if not ok then self.Pending[character] = nil; return nil, 'WEAPON PREPARATION FAILED' end
        end
        if backpack and #snapshot.Held > 0 then
            pcall(function()
                if options.UnequipTools then options.UnequipTools(humanoid)
                else humanoid:UnequipTools() end
            end)
            for _, tool in ipairs(snapshot.Held) do if tool.Parent == character then tool.Parent = backpack end end
        end
        return snapshot
    end
    function controller:Repair(snapshot)
        if not current(snapshot.Character) or self.Latest[snapshot.Character] ~= snapshot.Generation then return false end
        local character = snapshot.Character
        local function attachment(anchor)
            local part = character:FindFirstChild(anchor.Part)
            if not part or not part:IsA('BasePart') then return end
            local found = part:FindFirstChild(anchor.Name)
            if found and found:IsA('Attachment') then return found end
            if found then return end
            local saved = anchor.Size
            local ratio = Vector3.new(part.Size.X / math.max(.001, saved.X), part.Size.Y / math.max(.001, saved.Y), part.Size.Z / math.max(.001, saved.Z))
            found = Instance.new('Attachment')
            found.Name, found.CFrame = anchor.Name, CFrame.new(anchor.CFrame.Position * ratio) * anchor.CFrame.Rotation
            found.Parent = part
            return found
        end
        for _, anchor in ipairs(snapshot.Anchors) do attachment(anchor) end
        for _, display in ipairs(snapshot.Displays) do
            local target = display.Ref.Parent == character and display.Ref.Value
            if target then
                for _, binding in ipairs(display.Bindings) do
                    local endpoint = attachment(binding.Anchor)
                    if endpoint then
                        -- Keep any valid binding written by MM2 while the avatar
                        -- changed. Only repair a lost/outdated body endpoint.
                        local constraints = target == display.Target and {binding.Constraint} or target:GetDescendants()
                        for _, constraint in ipairs(constraints) do
                            if constraint:IsA('RigidConstraint') and constraint.Parent then
                                local otherProperty = binding.Property == 'Attachment0' and 'Attachment1' or 'Attachment0'
                                local other = constraint[otherProperty]
                                local value = constraint[binding.Property]
                                if other and other:IsDescendantOf(target) and (not value or not value:IsDescendantOf(character)) then
                                    constraint[binding.Property] = endpoint
                                end
                            end
                        end
                    end
                end
            end
        end
        return true
    end
    function controller:Finish(snapshot)
        if not snapshot or snapshot.Finished then return false end
        snapshot.Finished = true
        local valid = self:IsCurrent(snapshot)
        if valid then
            self:Repair(snapshot)
            local humanoid = snapshot.Character:FindFirstChildOfClass('Humanoid')
            if humanoid and humanoid.Health > 0 and not snapshot.Character:FindFirstChildOfClass('Tool') then
                for _, tool in ipairs(snapshot.Held) do
                    if tool.Parent == snapshot.Backpack then
                        pcall(function()
                            if options.EquipTool then options.EquipTool(humanoid, tool)
                            else humanoid:EquipTool(tool) end
                        end)
                        break
                    end
                end
            end
        end
        if self.Pending[snapshot.Character] == snapshot then self.Pending[snapshot.Character] = nil end
        if valid then
            if options.Refresh then options.Refresh() end
            -- A late MM2 display or scale update may arrive after the description.
            -- These bounded repairs never force a Tool back into the user's hand.
            for _, delay in ipairs({.15, .5, 1}) do
                task.delay(delay, function()
                    if self:IsCurrent(snapshot) and not self:IsChanging(snapshot.Character) then
                        self:Repair(snapshot)
                        if options.Refresh then options.Refresh() end
                    end
                end)
            end
        end
        return valid
    end
    function controller:Destroy()
        if not self.Active then return end
        for _, snapshot in pairs(self.Pending) do self:Finish(snapshot) end
        self.Active = false
        table.clear(self.Pending); table.clear(self.Latest)
    end
    Runtime.cleanup(function() controller:Destroy() end)
    return controller
end
Runtime.AvatarWeapons = Runtime.createAvatarWeaponController({
    ClearVisuals = function(snapshot)
        local displays = {}
        for _, display in ipairs(snapshot.Displays) do displays[display.Target] = true end
        for target in pairs(Runtime.Visual.States) do
            if target:IsDescendantOf(snapshot.Character) or displays[target] then Runtime.Visual.restore(target) end
        end
    end,
    Refresh = function() if Runtime.Active then applyEquippedWeaponVisuals() end end,
})
-- END AVATAR WEAPON BINDINGS

local function findWeaponInDatabase(weaponName)
    if not weaponName or weaponName == "" then
        return nil
    end

    local searchName = tostring(weaponName):lower():gsub("[^%w]", "")

    local function search(container, itemType)
        local bestItemId, bestDisplayName, bestScore = nil, nil, -1

        for itemId, data in pairs(container or {}) do
            if type(data) == "table" then
                local displayName = data.ItemName or data.Name or itemId
                local idText = tostring(itemId):lower():gsub("[^%w]", "")
                local nameText = tostring(displayName):lower():gsub("[^%w]", "")
                local score = -1

                if idText == searchName then
                    score = 100
                elseif nameText == searchName then
                    score = 90
                elseif idText:find(searchName, 1, true) or nameText:find(searchName, 1, true) then
                    score = 10
                end

                -- Prefer the actual Godly/Ancient item when cosmetic variants share a name.
                if score >= 0 then
                    if data.Rarity == "Ancient" then
                        score += 8
                    elseif data.Rarity == "Godly" then
                        score += 6
                    elseif data.Rarity == "Unique" then
                        score -= 6
                    end

                    if idText:find("silver", 1, true)
                        or idText:find("gold", 1, true)
                        or idText:find("bronze", 1, true)
                        or idText:find("purple", 1, true) then
                        score -= 12
                    end

                    if score > bestScore then
                        bestItemId, bestDisplayName, bestScore = itemId, displayName, score
                    end
                end
            end
        end

        if bestItemId then
            return bestItemId, itemType, bestDisplayName
        end
    end

    local itemId, itemType, displayName = search(sync.Weapons, "Weapons")
    if itemId then
        return itemId, itemType, displayName
    end

    return search(sync.Item, "Item")
end

local function spawnWeapon(weaponNameOrId, amount)
    local itemId, itemType, displayName = findWeaponInDatabase(weaponNameOrId)

    if not itemId then
        warn("[Carti Hub] Weapon not found: " .. tostring(weaponNameOrId))
        return false
    end

    amount = tonumber(amount) or 1
    amount = math.max(1, amount)

    if not getProfileOwnedTable(itemType) then
        warn("[Carti Hub] Could not find owned table for type: " .. tostring(itemType))
        return false
    end

    CartiHubAddFakeInventoryAmount(itemId, itemType, amount)

    refreshMainInventoryNow()

    for _ = 1, math.min(amount, 10) do
        pcall(function()
            itemPopupService:AddNewItem(itemId, itemType, 1)
        end)
    end

    return true
end

local function spawnWeaponById(itemId, itemType, amount)
    local itemData = sync[itemType] and sync[itemType][itemId]

    if not itemData then
        warn(("[Carti Hub] Weapon id not found: %s/%s"):format(tostring(itemType), tostring(itemId)))
        return false
    end

    amount = tonumber(amount) or 1
    amount = math.max(1, amount)

    if not getProfileOwnedTable(itemType) then
        warn("[Carti Hub] Could not find owned table for type: " .. tostring(itemType))
        return false
    end

    CartiHubAddFakeInventoryAmount(itemId, itemType, amount)

    refreshMainInventoryNow()

    for _ = 1, math.min(amount, 10) do
        pcall(function()
            itemPopupService:AddNewItem(itemId, itemType, 1)
        end)
    end

    local displayName = itemData.ItemName or itemData.Name or itemId
    return true
end

local function spawnWeaponByIdNoPopup(itemId, itemType, amount)
    local itemData = sync[itemType] and sync[itemType][itemId]

    if not itemData then
        warn(("[Carti Hub] Weapon id not found: %s/%s"):format(tostring(itemType), tostring(itemId)))
        return false
    end

    amount = tonumber(amount) or 1
    amount = math.max(1, amount)

    if not getProfileOwnedTable(itemType) then
        warn("[Carti Hub] Could not find owned table for type: " .. tostring(itemType))
        return false
    end

    CartiHubAddFakeInventoryAmount(itemId, itemType, amount)

    refreshMainInventoryNow()

    local displayName = itemData.ItemName or itemData.Name or itemId
    return true
end

local function normalizeItemText(value)
    return tostring(value or ""):lower():gsub("[^%w%?]", "")
end

local excludedBulkSpawnNames = {
    ["???"] = true,
    ["chroma???"] = true,
    ["bronzeraygun"] = true,
    ["goldraygun"] = true,
    ["redraygun"] = true,
    ["silverraygun"] = true,
    ["synthwave"] = true,
    ["niksscythe"] = true,
    ["gingerscythe"] = true,
    ["icecrusher"] = true,
    ["reaver"] = true,
}

local function isExcludedFromBulkSpawn(itemId, data)
    local idText = normalizeItemText(itemId)
    local nameText = normalizeItemText(data and (data.ItemName or data.Name))

    if excludedBulkSpawnNames[idText] or excludedBulkSpawnNames[nameText] then
        return true
    end

    return idText:find("exo", 1, true) ~= nil or nameText:find("exo", 1, true) ~= nil
end

local function spawnAllGodlyWeapons(amount)
    amount = tonumber(amount) or 1
    amount = math.max(1, amount)

    local spawnedCount = 0
    local seen = {}

    local function collect(container, itemType)
        for itemId, data in pairs(container or {}) do
            if type(data) == "table"
                and data.Rarity == "Godly"
                and not isExcludedFromBulkSpawn(itemId, data)
                and not seen[itemId] then
                seen[itemId] = true

                if getProfileOwnedTable(itemType) then
                    CartiHubAddFakeInventoryAmount(itemId, itemType, amount)
                    spawnedCount += 1
                end
            end
        end
    end

    collect(sync.Weapons, "Weapons")
    collect(sync.Item, "Item")
    refreshMainInventoryNow()

    return spawnedCount
end

local function spawnAllAncientWeapons(amount)
    amount = tonumber(amount) or 1
    amount = math.max(1, amount)

    local spawnedCount = 0
    local seen = {}

    local function collect(container, itemType)
        for itemId, data in pairs(container or {}) do
            if type(data) == "table"
                and data.Rarity == "Ancient"
                and not isExcludedFromBulkSpawn(itemId, data)
                and not seen[itemId] then
                seen[itemId] = true

                if getProfileOwnedTable(itemType) then
                    CartiHubAddFakeInventoryAmount(itemId, itemType, amount)
                    spawnedCount += 1
                end
            end
        end
    end

    collect(sync.Weapons, "Weapons")
    collect(sync.Item, "Item")
    refreshMainInventoryNow()

    return spawnedCount
end

local function isChromaWeapon(itemId, data)
    if type(data) ~= "table" then
        return false
    end

    local chromaTexture = data.ChromaTexture
    local chromaStaticLayer = data.ChromaStaticLayer
    local hasChromaTexture = chromaTexture ~= nil
        and chromaTexture ~= false
        and tostring(chromaTexture) ~= ""
    local hasChromaStaticLayer = chromaStaticLayer ~= nil
        and chromaStaticLayer ~= false
        and tostring(chromaStaticLayer) ~= ""

    if data.Chroma == true
        or data.IsChroma == true
        or hasChromaTexture
        or hasChromaStaticLayer then
        return true
    end

    local idText = tostring(itemId):lower()
    local nameText = tostring(data.ItemName or data.Name or ""):lower()

    return idText:find("chroma", 1, true) ~= nil
        or nameText:find("chroma", 1, true) ~= nil
end

local function spawnAllChromaWeapons(amount)
    amount = tonumber(amount) or 1
    amount = math.max(1, amount)

    local spawnedCount = 0
    local seen = {}

    local function collect(container, itemType)
        for itemId, data in pairs(container or {}) do
            if isChromaWeapon(itemId, data)
                and not isExcludedFromBulkSpawn(itemId, data)
                and not seen[itemId] then
                seen[itemId] = true

                if getProfileOwnedTable(itemType) then
                    CartiHubAddFakeInventoryAmount(itemId, itemType, amount)
                    spawnedCount += 1
                end
            end
        end
    end

    collect(sync.Weapons, "Weapons")
    collect(sync.Item, "Item")
    refreshMainInventoryNow()

    return spawnedCount
end

local function getRarityColor(rarity)
    local rarities = sync.Rarities or sync.Rarity
    local rarityData = rarities and rarities[rarity]

    if rarityData then
        if typeof(rarityData.Color) == "Color3" then
            return rarityData.Color
        end

        if type(rarityData.Hex) == "string" then
            local hex = rarityData.Hex:gsub("#", "")
            if #hex == 6 then
                return Color3.fromRGB(
                    tonumber(hex:sub(1, 2), 16),
                    tonumber(hex:sub(3, 4), 16),
                    tonumber(hex:sub(5, 6), 16)
                )
            end
        end
    end

    return Color3.fromRGB(83, 220, 255)
end

local function isSpawnerRarity(data)
    return data.Rarity == "Godly" or data.Rarity == "Ancient"
end

local function textHasEvoToken(text)
    text = tostring(text or ""):lower()
    return text == "evo"
        or text:find("^evo[%s_%-%./]") ~= nil
        or text:find("[%s_%-%./]evo[%s_%-%./]") ~= nil
        or text:find("[%s_%-%./]evo$") ~= nil
end

local function isEvoOrUntradeableWeapon(itemId, itemType)
    local data = sync[itemType] and sync[itemType][itemId]
    if type(data) ~= "table" then
        return false
    end

    if data.Tradeable == false
        or data.Tradable == false
        or data.NotTradeable == true
        or data.Untradeable == true
        or data.Untradable == true
        or data.IsEvo == true
        or data.Evo ~= nil
        or data.Evolution ~= nil
        or data.EvoData ~= nil
        or data.EvoBase ~= nil then
        return true
    end

    if data.EvoBaseID ~= nil
        or data.EvoIndex ~= nil
        or data.EvoLevel ~= nil
        or data.EvoLevels ~= nil
        or data.EvoXP ~= nil
        or data.EvolutionData ~= nil then
        return true
    end

    return textHasEvoToken(itemId)
        or textHasEvoToken(data.ItemName)
        or textHasEvoToken(data.Name)
end

local function canFakeTradeItem(itemId, itemType)
    return not isEvoOrUntradeableWeapon(itemId, itemType)
end

local function isOfferSpawnerWeapon(data)
    if type(data) ~= "table" then
        return false
    end

    if data.Rarity == "Unique" then
        return false
    end

    if data.Rarity ~= "Godly" and data.Rarity ~= "Ancient" then
        return false
    end

    local itemType = tostring(data.ItemType or data.Type or ""):lower()
    return itemType == "knife" or itemType == "sword" or itemType == "gun"
end

local SpawnerImageOverrides = {
    ["Chroma Icecream"] = "rbxthumb://type=Asset&w=150&h=150&id=90300177211738",
    ["Chroma Beachy"] = "rbxthumb://type=Asset&w=150&h=150&id=134952503728391",
    ["Chroma Sands"] = "rbxthumb://type=Asset&w=150&h=150&id=104927341820800",
    IcecreamChroma = "rbxthumb://type=Asset&w=150&h=150&id=90300177211738",
    BeachyChroma = "rbxthumb://type=Asset&w=150&h=150&id=134952503728391",
    SandsChroma = "rbxthumb://type=Asset&w=150&h=150&id=104927341820800",
}

task.spawn(function()
    pcall(function()
        game:GetService("ContentProvider"):PreloadAsync({
            SpawnerImageOverrides.IcecreamChroma,
            SpawnerImageOverrides.BeachyChroma,
            SpawnerImageOverrides.SandsChroma,
        })
    end)
end)

local function getSpawnerThumbnail(itemId, itemData)
    local displayName = itemData and (itemData.ItemName or itemData.Name) or itemId
    return SpawnerImageOverrides[displayName]
        or SpawnerImageOverrides[itemId]
        or (itemData and itemData.Image)
        or ""
end

local addSpecificItemToTheirOffer
local removeLastTheirOffer

local oldUi = safeParent():FindFirstChild("SakaModMenu")
if oldUi then
    oldUi:Destroy()
end

do
    local oldNebulaUi = safeParent():FindFirstChild("CartiHubNebula")
    if oldNebulaUi then
        oldNebulaUi:Destroy()
    end
end

SakaUI = Runtime.screenGui()
SakaUI.Name = "SakaModMenu"
SakaUI.ResetOnSpawn = false
SakaUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
SakaUI.Parent = safeParent()
Runtime.connect(SakaUI.Destroying, Runtime.shutdown)

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 448, 0, 540)
MainFrame.Position = UDim2.new(0.78, -224, 0.5, -270)
MainFrame.BackgroundColor3 = Color3.fromRGB(13, 4, 24)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = SakaUI

local Gradient = Instance.new("UIGradient")
Gradient.Rotation = 25
Gradient.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(4, 17, 27)),
    ColorSequenceKeypoint.new(0.24, Color3.fromRGB(8, 61, 70)),
    ColorSequenceKeypoint.new(0.52, Color3.fromRGB(9, 37, 78)),
    ColorSequenceKeypoint.new(0.77, Color3.fromRGB(58, 15, 78)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 8, 38)),
})
Gradient.Parent = MainFrame
Gradient.Enabled = false

Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 8)
MainFrame.ClipsDescendants = true

local BorderStroke = Instance.new("UIStroke")
BorderStroke.Color = Color3.fromRGB(255, 255, 255)
BorderStroke.Thickness = 1
BorderStroke.Transparency = 0.9
BorderStroke.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -154, 0, 34)
Title.Position = UDim2.new(0, 112, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "t.me/cartiscripts"
Title.TextColor3 = Color3.fromRGB(231, 222, 242)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 12
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = MainFrame

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 28, 0, 28)
CloseBtn.Position = UDim2.new(1, -34, 0, 3)
CloseBtn.BackgroundTransparency = 1
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.fromRGB(255, 128, 207)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 16
CloseBtn.Parent = MainFrame
Runtime.connect(CloseBtn.MouseButton1Click, function()
    Runtime.shutdown()
end)

local TopbarDivider = Instance.new("Frame")
TopbarDivider.Size = UDim2.new(1, 0, 0, 1)
TopbarDivider.Position = UDim2.new(0, 0, 0, 34)
TopbarDivider.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
TopbarDivider.BackgroundTransparency = 0.94
TopbarDivider.BorderSizePixel = 0
TopbarDivider.Parent = MainFrame

local TabContainer = Instance.new("ScrollingFrame")
TabContainer.CanvasSize = UDim2.new()
TabContainer.BorderSizePixel = 0
TabContainer.ScrollBarThickness = 0
TabContainer.ScrollingEnabled = false
TabContainer.Size = UDim2.new(0, 100, 1, -128)
TabContainer.Position = UDim2.new(0, 8, 0, 76)
TabContainer.BackgroundColor3 = Color3.fromRGB(16, 5, 30)
TabContainer.BackgroundTransparency = 0
TabContainer.Parent = MainFrame

local TabLayout = Instance.new("UIGridLayout")
TabLayout.CellSize = UDim2.new(1, -8, 0, 38)
TabLayout.CellPadding = UDim2.new(0, 0, 0, 4)
TabLayout.FillDirectionMaxCells = 1
TabLayout.SortOrder = Enum.SortOrder.LayoutOrder
TabLayout.Parent = TabContainer

local function CreateTabBtn(text, order)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 0, 0, 0)
    btn.BackgroundColor3 = Color3.fromRGB(19, 7, 33)
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(177, 157, 197)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 10
    btn.LayoutOrder = order
    btn.Parent = TabContainer
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
    return btn
end

local function CreateTabFrame()
    local frame = Instance.new("ScrollingFrame")
    frame.Size = UDim2.new(1, -128, 1, -62)
    frame.Position = UDim2.new(0, 116, 0, 50)
    frame.BackgroundTransparency = 1
    frame.BorderSizePixel = 0
    frame.ScrollBarThickness = 3
    frame.CanvasSize = UDim2.new(0, 0, 1.45, 0)
    frame.Visible = false
    frame.Parent = MainFrame

    local list = Instance.new("UIListLayout")
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Padding = UDim.new(0, 6)
    list.Parent = frame

    return frame
end

local function CreateBox(parent, placeholder)
    local box = Instance.new("TextBox")
    box.Size = UDim2.new(1, 0, 0, 34)
    box.BackgroundColor3 = Color3.fromRGB(20, 8, 34)
    box.PlaceholderText = placeholder
    box.PlaceholderColor3 = Color3.fromRGB(132, 112, 151)
    box.Text = ""
    box.TextColor3 = Color3.fromRGB(242, 231, 255)
    box.Font = Enum.Font.Gotham
    box.TextSize = 13
    box.Parent = parent
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 5)

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(186, 163, 211)
    stroke.Thickness = 1
    stroke.Transparency = 0.82
    stroke.Parent = box

    return box
end

local function CreateBtn(parent, text)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 38)
    btn.BackgroundColor3 = BUTTON_COLOR
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)

    Runtime.connect(btn.MouseEnter, function()
        TweenService:Create(btn, TweenInfo.new(0.2), { BackgroundColor3 = BUTTON_HOVER_COLOR }):Play()
    end)

    Runtime.connect(btn.MouseLeave, function()
        TweenService:Create(btn, TweenInfo.new(0.2), { BackgroundColor3 = BUTTON_COLOR }):Play()
    end)

    return btn
end

function Runtime.uiCanvasHeight(layout)
    local factor, ancestor = 1, layout.Parent
    while ancestor and not ancestor:IsA('ScreenGui') do
        local scale = ancestor:FindFirstChildOfClass('UIScale')
        if scale then factor *= scale.Scale end
        ancestor = ancestor.Parent
    end
    return layout.AbsoluteContentSize.Y / math.max(.01, factor)
end

function Runtime.bindUISlider(track, knob, callback)
    local binding = {}
    local hit = Instance.new('TextButton')
    hit.Name, hit.BackgroundTransparency, hit.Text = 'CartiHubSliderTouchTarget', 1, ''
    hit.Size, hit.Position, hit.AnchorPoint = UDim2.new(1, 0, 0, 36), UDim2.fromScale(.5, .5), Vector2.new(.5, .5)
    hit.ZIndex, hit.Parent = track.ZIndex + 1, track
    knob.ZIndex = hit.ZIndex + 1
    local function update(input)
        if track.AbsoluteSize.X > 0 then callback(math.clamp((input.Position.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)) end
    end
    function binding.Begin(input)
        if binding.Pointer then return end
        if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
        binding.Pointer = input
        update(input)
    end
    function binding.Move(input)
        local pointer = binding.Pointer
        if pointer and (input == pointer or (pointer.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement)) then update(input) end
    end
    function binding.End(input) if input == binding.Pointer then binding.Pointer = nil end end
    Runtime.connect(hit.InputBegan, binding.Begin)
    Runtime.connect(knob.InputBegan, binding.Begin)
    Runtime.connect(UserInputService.InputChanged, binding.Move)
    Runtime.connect(UserInputService.InputEnded, binding.End)
    return binding
end

local function CreateSlider(parent, text, min, max, defaultVal, step, callback)
    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, 0, 0, 50)
    container.BackgroundTransparency = 1
    container.Parent = parent

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 0, 22)
    label.BackgroundTransparency = 1
    label.Text = text .. ": " .. defaultVal
    label.Font = Enum.Font.GothamBold
    label.TextColor3 = Color3.fromRGB(230, 200, 255)
    label.TextSize = 13
    label.Parent = container

    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(1, -10, 0, 10)
    bg.Position = UDim2.new(0, 5, 0, 28)
    bg.BackgroundColor3 = Color3.fromRGB(13, 22, 46)
    bg.Parent = container
    Instance.new("UICorner", bg).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame")
    fill.BackgroundColor3 = BUTTON_COLOR
    fill.Size = UDim2.new((defaultVal - min) / (max - min), 0, 1, 0)
    fill.Parent = bg
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("TextButton")
    knob.Size = UDim2.new(0, 34, 0, 18)
    knob.Position = UDim2.new(1, -17, 0.5, -9)
    knob.BackgroundColor3 = Color3.fromRGB(210, 245, 255)
    knob.Text = tostring(defaultVal)
    knob.TextColor3 = Color3.fromRGB(15, 25, 52)
    knob.Font = Enum.Font.GothamBold
    knob.TextSize = 10
    knob.Parent = fill
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    Runtime.bindUISlider(bg, knob, function(percent)
        local rawVal = min + ((max - min) * percent)
        local val = math.clamp(math.floor(rawVal / step + .5) * step, min, max)
        fill.Size = UDim2.new((val - min) / (max - min), 0, 1, 0)
        label.Text, knob.Text = text .. ': ' .. val, tostring(val)
        callback(val)
    end)
end

local SpawnerTabBtn = CreateTabBtn("Spawner", 1)
local TradeTabBtn = CreateTabBtn("Trade", 2)
UpgradingTabBtn = CreateTabBtn("Upgrading", 3)
BlockTabBtn = CreateTabBtn("Block", 4)
local SettingsTabBtn = CreateTabBtn("Settings", 5)
local KeybindsTabBtn = CreateTabBtn("Keys", 6)
Runtime.NPCTab = CreateTabBtn("NPCs", 7)

local SpawnerFrame = CreateTabFrame()
local TradeFrame = CreateTabFrame()
UpgradingFrame = CreateTabFrame()
BlockFrame = CreateTabFrame()
local SettingsFrame = CreateTabFrame()
local KeybindsFrame = CreateTabFrame()
Runtime.NPCFrame = CreateTabFrame()
SpawnerFrame.Visible = true
SpawnerTabBtn.BackgroundColor3 = BUTTON_HOVER_COLOR

task.spawn(function()
    local wrapper = Instance.new("CanvasGroup")
    wrapper.Name = "CartiHubNebulaWrapper"
    wrapper.Size = UDim2.fromScale(1, 1)
    wrapper.BackgroundColor3 = Color3.fromRGB(13, 4, 24)
    wrapper.BorderSizePixel = 0
    wrapper.ZIndex = 1
    wrapper.Parent = MainFrame
    Instance.new("UICorner", wrapper).CornerRadius = UDim.new(0, 8)

    local topbar = Instance.new("Frame")
    topbar.Name = "NebulaTopbar"
    topbar.Size = UDim2.new(1, 0, 0, 34)
    topbar.BackgroundColor3 = Color3.fromRGB(16, 5, 30)
    topbar.BorderSizePixel = 0
    topbar.ZIndex = 1
    topbar.Parent = wrapper
    Instance.new("UICorner", topbar).CornerRadius = UDim.new(0, 8)

    local topbarFill = Instance.new("Frame")
    topbarFill.Size = UDim2.new(1, 0, 0.5, 0)
    topbarFill.Position = UDim2.new(0, 0, 0.5, 0)
    topbarFill.BackgroundColor3 = Color3.fromRGB(16, 5, 30)
    topbarFill.BorderSizePixel = 0
    topbarFill.ZIndex = 1
    topbarFill.Parent = topbar

    local rail = Instance.new("Frame")
    rail.Name = "NebulaRibbon"
    rail.Size = UDim2.new(0, 108, 1, -42)
    rail.Position = UDim2.new(0, 4, 0, 38)
    rail.BackgroundColor3 = Color3.fromRGB(16, 5, 30)
    rail.BorderSizePixel = 0
    rail.ZIndex = 1
    rail.Parent = wrapper
    Instance.new("UICorner", rail).CornerRadius = UDim.new(0, 6)

    local content = Instance.new("Frame")
    content.Name = "NebulaPageCanvas"
    content.Size = UDim2.new(1, -122, 1, -46)
    content.Position = UDim2.new(0, 116, 0, 40)
    content.BackgroundColor3 = Color3.fromRGB(17, 6, 29)
    content.BorderSizePixel = 0
    content.ZIndex = 1
    content.Parent = wrapper
    Instance.new("UICorner", content).CornerRadius = UDim.new(0, 6)

    local sectionLine = Instance.new("Frame")
    sectionLine.Size = UDim2.new(1, -16, 0, 1)
    sectionLine.Position = UDim2.new(0, 8, 0, 32)
    sectionLine.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    sectionLine.BackgroundTransparency = 0.94
    sectionLine.BorderSizePixel = 0
    sectionLine.ZIndex = 1
    sectionLine.Parent = rail

    local railTitle = Instance.new("TextLabel")
    railTitle.Size = UDim2.new(1, -16, 0, 20)
    railTitle.Position = UDim2.new(0, 8, 0, 7)
    railTitle.BackgroundTransparency = 1
    railTitle.Text = "CONTROL PANEL"
    railTitle.TextColor3 = Color3.fromRGB(121, 102, 140)
    railTitle.Font = Enum.Font.GothamBold
    railTitle.TextSize = 8
    railTitle.TextXAlignment = Enum.TextXAlignment.Left
    railTitle.ZIndex = 2
    railTitle.Parent = rail

    local pageCaption = Instance.new("TextLabel")
    pageCaption.Name = "NebulaPageCaption"
    pageCaption.Size = UDim2.new(1, -20, 0, 20)
    pageCaption.Position = UDim2.new(0, 126, 0, 41)
    pageCaption.BackgroundTransparency = 1
    pageCaption.Text = "MM2 CLIENT CONTROLS"
    pageCaption.TextColor3 = Color3.fromRGB(132, 112, 151)
    pageCaption.Font = Enum.Font.GothamBold
    pageCaption.TextSize = 8
    pageCaption.TextXAlignment = Enum.TextXAlignment.Left
    pageCaption.ZIndex = 2
    pageCaption.Parent = MainFrame

    local profile = Instance.new("Frame")
    profile.Name = "NebulaProfile"
    profile.Size = UDim2.new(0, 92, 0, 42)
    profile.Position = UDim2.new(0, 12, 1, -48)
    profile.BackgroundColor3 = Color3.fromRGB(22, 8, 39)
    profile.BorderSizePixel = 0
    profile.ZIndex = 2
    profile.Parent = MainFrame
    Instance.new("UICorner", profile).CornerRadius = UDim.new(0, 5)

    local avatar = Instance.new("ImageLabel")
    avatar.Size = UDim2.new(0, 24, 0, 24)
    avatar.Position = UDim2.new(0, 7, 0.5, -12)
    avatar.BackgroundColor3 = Color3.fromRGB(41, 20, 61)
    avatar.BorderSizePixel = 0
    avatar.Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(localPlayer.UserId)
    avatar.ZIndex = 3
    avatar.Parent = profile
    Instance.new("UICorner", avatar).CornerRadius = UDim.new(1, 0)

    local username = Instance.new("TextLabel")
    username.Size = UDim2.new(1, -40, 0, 16)
    username.Position = UDim2.new(0, 36, 0, 6)
    username.BackgroundTransparency = 1
    username.Text = localPlayer.Name
    username.TextColor3 = Color3.fromRGB(225, 215, 238)
    username.Font = Enum.Font.GothamBold
    username.TextSize = 8
    username.TextTruncate = Enum.TextTruncate.AtEnd
    username.TextXAlignment = Enum.TextXAlignment.Left
    username.ZIndex = 3
    username.Parent = profile

    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -40, 0, 13)
    status.Position = UDim2.new(0, 36, 0, 21)
    status.BackgroundTransparency = 1
    status.Text = "SESSION ACTIVE"
    status.TextColor3 = Color3.fromRGB(149, 117, 178)
    status.Font = Enum.Font.Gotham
    status.TextSize = 7
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.ZIndex = 3
    status.Parent = profile

    for _, tab in ipairs({ SpawnerTabBtn, TradeTabBtn, UpgradingTabBtn, BlockTabBtn, SettingsTabBtn, KeybindsTabBtn, Runtime.NPCTab }) do
        tab.Position = UDim2.new(0, 4, 0, 0)
        tab.Size = UDim2.new(1, -8, 0, 38)
        tab.TextXAlignment = Enum.TextXAlignment.Left
        tab.TextColor3 = Color3.fromRGB(182, 160, 203)
        tab.ZIndex = 3

        local padding = Instance.new("UIPadding")
        padding.PaddingLeft = UDim.new(0, 12)
        padding.Parent = tab

        local accent = Instance.new("Frame")
        accent.Name = "NebulaActiveAccent"
        accent.Size = UDim2.new(0, 2, 0, 18)
        accent.Position = UDim2.new(0, 0, 0.5, -9)
        accent.BackgroundColor3 = Color3.fromRGB(185, 118, 255)
        accent.BorderSizePixel = 0
        accent.Visible = tab == SpawnerTabBtn
        accent.ZIndex = 4
        accent.Parent = tab
    end

    for _, root in ipairs({ Title, CloseBtn, TopbarDivider, TabContainer, SpawnerFrame, TradeFrame, UpgradingFrame, BlockFrame, SettingsFrame, KeybindsFrame, Runtime.NPCFrame }) do
        if root:IsA("GuiObject") then
            root.ZIndex = math.max(root.ZIndex, 3)
        end

        for _, descendant in ipairs(root:GetDescendants()) do
            if descendant:IsA("GuiObject") then
                descendant.ZIndex = math.max(descendant.ZIndex, 3)
            end
        end
    end
end)

CartiHubBlockSessionBox = CreateBox(BlockFrame, "RBXSECURITY session")
CartiHubBlockTrackerBox = CreateBox(BlockFrame, "RBXEventTrackerV2 value")
_G.CartiHubGetBlockCredentials = function()
    return CartiHubBlockSessionBox and CartiHubBlockSessionBox.Text or "",
        CartiHubBlockTrackerBox and CartiHubBlockTrackerBox.Text or "",
        ""
end

_G.CartiHubPlayerListBlockButtonsEnabled = false
CartiHubPlayerListBlockToggleBtn = CreateBtn(BlockFrame, "PLAYERLIST BLOCK: OFF")
Runtime.connect(CartiHubPlayerListBlockToggleBtn.MouseButton1Click, function()
    local enabled = not _G.CartiHubPlayerListBlockButtonsEnabled
    _G.CartiHubPlayerListBlockButtonsEnabled = enabled
    CartiHubPlayerListBlockToggleBtn.Text = enabled and "PLAYERLIST BLOCK: ON" or "PLAYERLIST BLOCK: OFF"
    CartiHubPlayerListBlockToggleBtn.BackgroundColor3 = enabled and BUTTON_HOVER_COLOR or BUTTON_COLOR

    local setEnabled = _G.CartiHubSetPlayerListBlockButtonsEnabled
    if type(setEnabled) == "function" then
        setEnabled(enabled)
    end
end)

local SPAWNER_COLS = 5
local SPAWNER_BOX_SIZE = 78
local SPAWNER_PADDING = 5
local SPAWNER_NAME_HEIGHT = 21
local SPAWNER_RARITY_HEIGHT = 18
local SPAWNER_SLIDER_HEIGHT = 54
local spawnerWidth = (SPAWNER_BOX_SIZE + SPAWNER_PADDING) * SPAWNER_COLS + SPAWNER_PADDING + 20

local SpawnerGuiFrame = Instance.new("Frame")
SpawnerGuiFrame.Name = "WeaponSpawnerGUI"
SpawnerGuiFrame.Size = UDim2.new(0, spawnerWidth, 0, 470)
SpawnerGuiFrame.Position = UDim2.new(0.5, -(spawnerWidth / 2), 0.5, -235)
SpawnerGuiFrame.BackgroundColor3 = Color3.fromRGB(9, 14, 31)
SpawnerGuiFrame.BorderSizePixel = 0
SpawnerGuiFrame.Active = true
SpawnerGuiFrame.Draggable = true
SpawnerGuiFrame.Visible = false
SpawnerGuiFrame.Parent = SakaUI
Instance.new("UICorner", SpawnerGuiFrame).CornerRadius = UDim.new(0, 10)

local PopupStroke = Instance.new("UIStroke")
PopupStroke.Color = Color3.fromRGB(83, 220, 255)
PopupStroke.Thickness = 1
PopupStroke.Transparency = 0.15
PopupStroke.Parent = SpawnerGuiFrame

local PopupTitle = Instance.new("TextLabel")
PopupTitle.Size = UDim2.new(1, -40, 0, 35)
PopupTitle.Position = UDim2.new(0, 15, 0, 5)
PopupTitle.BackgroundTransparency = 1
PopupTitle.Text = "Weapon Spawner"
PopupTitle.TextColor3 = Color3.fromRGB(210, 245, 255)
PopupTitle.Font = Enum.Font.GothamBold
PopupTitle.TextSize = 18
PopupTitle.TextXAlignment = Enum.TextXAlignment.Left
PopupTitle.Parent = SpawnerGuiFrame

local PopupCloseBtn = Instance.new("TextButton")
PopupCloseBtn.Size = UDim2.new(0, 28, 0, 28)
PopupCloseBtn.Position = UDim2.new(1, -38, 0, 6)
PopupCloseBtn.BackgroundTransparency = 1
PopupCloseBtn.Text = "X"
PopupCloseBtn.TextColor3 = Color3.fromRGB(255, 128, 207)
PopupCloseBtn.Font = Enum.Font.GothamBold
PopupCloseBtn.TextSize = 18
PopupCloseBtn.Parent = SpawnerGuiFrame
Runtime.connect(PopupCloseBtn.MouseButton1Click, function()
    SpawnerGuiFrame.Visible = false
end)

local WeaponSearchBox = Instance.new("TextBox")
WeaponSearchBox.Size = UDim2.new(1, -16, 0, 30)
WeaponSearchBox.Position = UDim2.new(0, 8, 0, 42)
WeaponSearchBox.BackgroundColor3 = Color3.fromRGB(13, 22, 46)
WeaponSearchBox.BorderSizePixel = 0
WeaponSearchBox.PlaceholderText = "Search weapons..."
WeaponSearchBox.PlaceholderColor3 = Color3.fromRGB(120, 151, 191)
WeaponSearchBox.Text = ""
WeaponSearchBox.TextColor3 = Color3.fromRGB(220, 240, 255)
WeaponSearchBox.Font = Enum.Font.Gotham
WeaponSearchBox.TextSize = 13
WeaponSearchBox.ClearTextOnFocus = false
WeaponSearchBox.Parent = SpawnerGuiFrame
Instance.new("UICorner", WeaponSearchBox).CornerRadius = UDim.new(0, 8)

local WeaponScrollFrame = Instance.new("ScrollingFrame")
WeaponScrollFrame.Size = UDim2.new(1, -10, 1, -(55 + SPAWNER_SLIDER_HEIGHT))
WeaponScrollFrame.Position = UDim2.new(0, 5, 0, 78)
WeaponScrollFrame.BackgroundTransparency = 1
WeaponScrollFrame.BorderSizePixel = 0
WeaponScrollFrame.ScrollBarThickness = 4
WeaponScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
WeaponScrollFrame.ScrollBarImageColor3 = Color3.fromRGB(83, 220, 255)
WeaponScrollFrame.Parent = SpawnerGuiFrame

local WeaponGrid = Instance.new("UIGridLayout")
WeaponGrid.CellSize = UDim2.new(0, SPAWNER_BOX_SIZE, 0, SPAWNER_BOX_SIZE + SPAWNER_NAME_HEIGHT + SPAWNER_RARITY_HEIGHT)
WeaponGrid.CellPadding = UDim2.new(0, SPAWNER_PADDING, 0, SPAWNER_PADDING)
WeaponGrid.FillDirectionMaxCells = SPAWNER_COLS
WeaponGrid.SortOrder = Enum.SortOrder.LayoutOrder
WeaponGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
WeaponGrid.Parent = WeaponScrollFrame

Runtime.connect(WeaponGrid:GetPropertyChangedSignal("AbsoluteContentSize"), function()
    WeaponScrollFrame.CanvasSize = UDim2.new(0, 0, 0, Runtime.uiCanvasHeight(WeaponGrid) + 10)
end)

local PopupSliderFrame = Instance.new("Frame")
PopupSliderFrame.Size = UDim2.new(1, -16, 0, SPAWNER_SLIDER_HEIGHT)
PopupSliderFrame.Position = UDim2.new(0, 8, 1, -(SPAWNER_SLIDER_HEIGHT + 6))
PopupSliderFrame.BackgroundColor3 = Color3.fromRGB(12, 21, 45)
PopupSliderFrame.BorderSizePixel = 0
PopupSliderFrame.Parent = SpawnerGuiFrame
Instance.new("UICorner", PopupSliderFrame).CornerRadius = UDim.new(0, 10)

local PopupAmountLabel = Instance.new("TextLabel")
PopupAmountLabel.Size = UDim2.new(1, -16, 0, 20)
PopupAmountLabel.Position = UDim2.new(0, 8, 0, 4)
PopupAmountLabel.BackgroundTransparency = 1
PopupAmountLabel.Text = "Spawn Amount: " .. currentWeaponAmount
PopupAmountLabel.TextColor3 = Color3.fromRGB(210, 245, 255)
PopupAmountLabel.Font = Enum.Font.GothamBold
PopupAmountLabel.TextSize = 13
PopupAmountLabel.TextXAlignment = Enum.TextXAlignment.Left
PopupAmountLabel.Parent = PopupSliderFrame

local PopupSliderTrack = Instance.new("Frame")
PopupSliderTrack.Size = UDim2.new(1, -22, 0, 10)
PopupSliderTrack.Position = UDim2.new(0, 11, 0, 32)
PopupSliderTrack.BackgroundColor3 = Color3.fromRGB(30, 12, 55)
PopupSliderTrack.BorderSizePixel = 0
PopupSliderTrack.Parent = PopupSliderFrame
Instance.new("UICorner", PopupSliderTrack).CornerRadius = UDim.new(1, 0)

local PopupSliderFill = Instance.new("Frame")
PopupSliderFill.Size = UDim2.new(0, 0, 1, 0)
PopupSliderFill.BackgroundColor3 = BUTTON_COLOR
PopupSliderFill.BorderSizePixel = 0
PopupSliderFill.Parent = PopupSliderTrack
Instance.new("UICorner", PopupSliderFill).CornerRadius = UDim.new(1, 0)

local PopupSliderKnob = Instance.new("TextButton")
PopupSliderKnob.Size = UDim2.new(0, 34, 0, 18)
PopupSliderKnob.Position = UDim2.new(0, -17, 0.5, -9)
PopupSliderKnob.BackgroundColor3 = Color3.fromRGB(210, 245, 255)
PopupSliderKnob.Text = tostring(currentWeaponAmount)
PopupSliderKnob.TextColor3 = Color3.fromRGB(15, 25, 52)
PopupSliderKnob.Font = Enum.Font.GothamBold
PopupSliderKnob.TextSize = 10
PopupSliderKnob.Parent = PopupSliderFill
Instance.new("UICorner", PopupSliderKnob).CornerRadius = UDim.new(1, 0)

local function setPopupSpawnAmountFromPercent(percent)
    local minAmount = 1
    local maxAmount = MAX_WEAPON_AMOUNT
    percent = math.clamp(percent, 0, 1)

    local value = math.floor(minAmount + ((maxAmount - minAmount) * percent) + 0.5)
    value = math.clamp(value, minAmount, maxAmount)

    currentWeaponAmount = value
    PopupAmountLabel.Text = "Spawn Amount: " .. value
    PopupSliderKnob.Text = tostring(value)
    PopupSliderFill.Size = UDim2.new((value - minAmount) / (maxAmount - minAmount), 0, 1, 0)
end

Runtime.bindUISlider(PopupSliderTrack, PopupSliderKnob, setPopupSpawnAmountFromPercent)

local function filterSpawnerCards(scrollFrame, query)
    query = tostring(query or ""):lower()

    for _, child in ipairs(scrollFrame:GetChildren()) do
        if child:IsA("GuiObject") and child:GetAttribute("SearchText") then
            child.Visible = query == "" or string.find(child:GetAttribute("SearchText"), query, 1, true) ~= nil
        end
    end
end

Runtime.connect(WeaponSearchBox:GetPropertyChangedSignal("Text"), function()
    filterSpawnerCards(WeaponScrollFrame, WeaponSearchBox.Text)
end)

local OFFER_SPAWNER_COLS = 4
local offerSpawnerWidth = (SPAWNER_BOX_SIZE + SPAWNER_PADDING) * OFFER_SPAWNER_COLS + SPAWNER_PADDING + 20

local OfferSpawnerGuiFrame = Instance.new("Frame")
OfferSpawnerGuiFrame.Name = "OfferSpawnerGUI"
OfferSpawnerGuiFrame.Size = UDim2.new(0, offerSpawnerWidth, 0, 470)
OfferSpawnerGuiFrame.Position = UDim2.new(0.5, -(offerSpawnerWidth / 2), 0.5, -235)
OfferSpawnerGuiFrame.BackgroundColor3 = Color3.fromRGB(9, 14, 31)
OfferSpawnerGuiFrame.BorderSizePixel = 0
OfferSpawnerGuiFrame.Active = true
OfferSpawnerGuiFrame.Draggable = true
OfferSpawnerGuiFrame.Visible = false
OfferSpawnerGuiFrame.Parent = SakaUI
Instance.new("UICorner", OfferSpawnerGuiFrame).CornerRadius = UDim.new(0, 10)

local OfferPopupStroke = Instance.new("UIStroke")
OfferPopupStroke.Color = Color3.fromRGB(83, 220, 255)
OfferPopupStroke.Thickness = 1
OfferPopupStroke.Transparency = 0.15
OfferPopupStroke.Parent = OfferSpawnerGuiFrame

local OfferPopupTitle = Instance.new("TextLabel")
OfferPopupTitle.Size = UDim2.new(1, -40, 0, 35)
OfferPopupTitle.Position = UDim2.new(0, 15, 0, 5)
OfferPopupTitle.BackgroundTransparency = 1
OfferPopupTitle.Text = "Offer Spawner"
OfferPopupTitle.TextColor3 = Color3.fromRGB(210, 245, 255)
OfferPopupTitle.Font = Enum.Font.GothamBold
OfferPopupTitle.TextSize = 18
OfferPopupTitle.TextXAlignment = Enum.TextXAlignment.Left
OfferPopupTitle.Parent = OfferSpawnerGuiFrame

local OfferPopupCloseBtn = Instance.new("TextButton")
OfferPopupCloseBtn.Size = UDim2.new(0, 28, 0, 28)
OfferPopupCloseBtn.Position = UDim2.new(1, -38, 0, 6)
OfferPopupCloseBtn.BackgroundTransparency = 1
OfferPopupCloseBtn.Text = "X"
OfferPopupCloseBtn.TextColor3 = Color3.fromRGB(255, 128, 207)
OfferPopupCloseBtn.Font = Enum.Font.GothamBold
OfferPopupCloseBtn.TextSize = 18
OfferPopupCloseBtn.Parent = OfferSpawnerGuiFrame
Runtime.connect(OfferPopupCloseBtn.MouseButton1Click, function()
    OfferSpawnerGuiFrame.Visible = false
end)

local OfferSearchBox = Instance.new("TextBox")
OfferSearchBox.Size = UDim2.new(1, -16, 0, 30)
OfferSearchBox.Position = UDim2.new(0, 8, 0, 42)
OfferSearchBox.BackgroundColor3 = Color3.fromRGB(13, 22, 46)
OfferSearchBox.BorderSizePixel = 0
OfferSearchBox.PlaceholderText = "Search offer items..."
OfferSearchBox.PlaceholderColor3 = Color3.fromRGB(120, 151, 191)
OfferSearchBox.Text = ""
OfferSearchBox.TextColor3 = Color3.fromRGB(220, 240, 255)
OfferSearchBox.Font = Enum.Font.Gotham
OfferSearchBox.TextSize = 13
OfferSearchBox.ClearTextOnFocus = false
OfferSearchBox.Parent = OfferSpawnerGuiFrame
Instance.new("UICorner", OfferSearchBox).CornerRadius = UDim.new(0, 8)

local OfferWeaponScrollFrame = Instance.new("ScrollingFrame")
OfferWeaponScrollFrame.Size = UDim2.new(1, -10, 1, -138)
OfferWeaponScrollFrame.Position = UDim2.new(0, 5, 0, 78)
OfferWeaponScrollFrame.BackgroundTransparency = 1
OfferWeaponScrollFrame.BorderSizePixel = 0
OfferWeaponScrollFrame.ScrollBarThickness = 4
OfferWeaponScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
OfferWeaponScrollFrame.ScrollBarImageColor3 = Color3.fromRGB(83, 220, 255)
OfferWeaponScrollFrame.Parent = OfferSpawnerGuiFrame

local OfferWeaponGrid = Instance.new("UIGridLayout")
OfferWeaponGrid.CellSize = UDim2.new(0, SPAWNER_BOX_SIZE, 0, SPAWNER_BOX_SIZE + SPAWNER_NAME_HEIGHT + SPAWNER_RARITY_HEIGHT)
OfferWeaponGrid.CellPadding = UDim2.new(0, SPAWNER_PADDING, 0, SPAWNER_PADDING)
OfferWeaponGrid.FillDirectionMaxCells = OFFER_SPAWNER_COLS
OfferWeaponGrid.SortOrder = Enum.SortOrder.LayoutOrder
OfferWeaponGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
OfferWeaponGrid.Parent = OfferWeaponScrollFrame

Runtime.connect(OfferWeaponGrid:GetPropertyChangedSignal("AbsoluteContentSize"), function()
    OfferWeaponScrollFrame.CanvasSize = UDim2.new(0, 0, 0, Runtime.uiCanvasHeight(OfferWeaponGrid) + 10)
end)

local OfferDeleteLastBtn = Instance.new("TextButton")
OfferDeleteLastBtn.Size = UDim2.new(1, -16, 0, 42)
OfferDeleteLastBtn.Position = UDim2.new(0, 8, 1, -50)
OfferDeleteLastBtn.BackgroundColor3 = BUTTON_COLOR
OfferDeleteLastBtn.Text = "DELETE LAST OFFER SLOT"
OfferDeleteLastBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
OfferDeleteLastBtn.Font = Enum.Font.GothamBold
OfferDeleteLastBtn.TextSize = 13
OfferDeleteLastBtn.Parent = OfferSpawnerGuiFrame
Instance.new("UICorner", OfferDeleteLastBtn).CornerRadius = UDim.new(0, 8)

Runtime.connect(OfferDeleteLastBtn.MouseEnter, function()
    TweenService:Create(OfferDeleteLastBtn, TweenInfo.new(0.2), { BackgroundColor3 = BUTTON_HOVER_COLOR }):Play()
end)

Runtime.connect(OfferDeleteLastBtn.MouseLeave, function()
    TweenService:Create(OfferDeleteLastBtn, TweenInfo.new(0.2), { BackgroundColor3 = BUTTON_COLOR }):Play()
end)

Runtime.connect(OfferDeleteLastBtn.MouseButton1Click, function()
    if removeLastTheirOffer then
        removeLastTheirOffer()
    end
end)

Runtime.connect(OfferSearchBox:GetPropertyChangedSignal("Text"), function()
    filterSpawnerCards(OfferWeaponScrollFrame, OfferSearchBox.Text)
end)

local RealisticSpawnerGuiFrame
local populateRealisticSpawner

do
    local selectedRealisticWeapons = {}
    local didPopulateRealisticSpawner = false

    RealisticSpawnerGuiFrame = Instance.new("Frame")
    RealisticSpawnerGuiFrame.Name = "RealisticSpawnerGUI"
    RealisticSpawnerGuiFrame.Size = UDim2.new(0, spawnerWidth, 0, 500)
    RealisticSpawnerGuiFrame.Position = UDim2.new(0.5, -(spawnerWidth / 2), 0.5, -250)
    RealisticSpawnerGuiFrame.BackgroundColor3 = Color3.fromRGB(9, 14, 31)
    RealisticSpawnerGuiFrame.BorderSizePixel = 0
    RealisticSpawnerGuiFrame.Active = true
    RealisticSpawnerGuiFrame.Draggable = true
    RealisticSpawnerGuiFrame.Visible = false
    RealisticSpawnerGuiFrame.Parent = SakaUI
    Instance.new("UICorner", RealisticSpawnerGuiFrame).CornerRadius = UDim.new(0, 10)

    local realisticStroke = Instance.new("UIStroke")
    realisticStroke.Color = Color3.fromRGB(83, 220, 255)
    realisticStroke.Thickness = 1
    realisticStroke.Transparency = 0.15
    realisticStroke.Parent = RealisticSpawnerGuiFrame

    local realisticTitle = Instance.new("TextLabel")
    realisticTitle.Size = UDim2.new(1, -40, 0, 35)
    realisticTitle.Position = UDim2.new(0, 15, 0, 5)
    realisticTitle.BackgroundTransparency = 1
    realisticTitle.Text = "Realistic Spawner"
    realisticTitle.TextColor3 = Color3.fromRGB(210, 245, 255)
    realisticTitle.Font = Enum.Font.GothamBold
    realisticTitle.TextSize = 18
    realisticTitle.TextXAlignment = Enum.TextXAlignment.Left
    realisticTitle.Parent = RealisticSpawnerGuiFrame

    local realisticCloseBtn = Instance.new("TextButton")
    realisticCloseBtn.Size = UDim2.new(0, 28, 0, 28)
    realisticCloseBtn.Position = UDim2.new(1, -38, 0, 6)
    realisticCloseBtn.BackgroundTransparency = 1
    realisticCloseBtn.Text = "X"
    realisticCloseBtn.TextColor3 = Color3.fromRGB(255, 128, 207)
    realisticCloseBtn.Font = Enum.Font.GothamBold
    realisticCloseBtn.TextSize = 18
    realisticCloseBtn.Parent = RealisticSpawnerGuiFrame
    Runtime.connect(realisticCloseBtn.MouseButton1Click, function()
        RealisticSpawnerGuiFrame.Visible = false
    end)

    local realisticSearchBox = Instance.new("TextBox")
    realisticSearchBox.Size = UDim2.new(1, -16, 0, 30)
    realisticSearchBox.Position = UDim2.new(0, 8, 0, 42)
    realisticSearchBox.BackgroundColor3 = Color3.fromRGB(13, 22, 46)
    realisticSearchBox.BorderSizePixel = 0
    realisticSearchBox.PlaceholderText = "Search weapons..."
    realisticSearchBox.PlaceholderColor3 = Color3.fromRGB(120, 151, 191)
    realisticSearchBox.Text = ""
    realisticSearchBox.TextColor3 = Color3.fromRGB(220, 240, 255)
    realisticSearchBox.Font = Enum.Font.Gotham
    realisticSearchBox.TextSize = 13
    realisticSearchBox.ClearTextOnFocus = false
    realisticSearchBox.Parent = RealisticSpawnerGuiFrame
    Instance.new("UICorner", realisticSearchBox).CornerRadius = UDim.new(0, 8)

    local realisticScrollFrame = Instance.new("ScrollingFrame")
    realisticScrollFrame.Size = UDim2.new(1, -10, 1, -156)
    realisticScrollFrame.Position = UDim2.new(0, 5, 0, 78)
    realisticScrollFrame.BackgroundTransparency = 1
    realisticScrollFrame.BorderSizePixel = 0
    realisticScrollFrame.ScrollBarThickness = 4
    realisticScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    realisticScrollFrame.ScrollBarImageColor3 = Color3.fromRGB(83, 220, 255)
    realisticScrollFrame.Parent = RealisticSpawnerGuiFrame

    local realisticGrid = Instance.new("UIGridLayout")
    realisticGrid.CellSize = UDim2.new(0, SPAWNER_BOX_SIZE, 0, SPAWNER_BOX_SIZE + SPAWNER_NAME_HEIGHT + SPAWNER_RARITY_HEIGHT)
    realisticGrid.CellPadding = UDim2.new(0, SPAWNER_PADDING, 0, SPAWNER_PADDING)
    realisticGrid.FillDirectionMaxCells = SPAWNER_COLS
    realisticGrid.SortOrder = Enum.SortOrder.LayoutOrder
    realisticGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
    realisticGrid.Parent = realisticScrollFrame

    Runtime.connect(realisticGrid:GetPropertyChangedSignal("AbsoluteContentSize"), function()
        realisticScrollFrame.CanvasSize = UDim2.new(0, 0, 0, Runtime.uiCanvasHeight(realisticGrid) + 10)
    end)

    local controlsFrame = Instance.new("Frame")
    controlsFrame.Size = UDim2.new(1, -16, 0, 68)
    controlsFrame.Position = UDim2.new(0, 8, 1, -76)
    controlsFrame.BackgroundColor3 = Color3.fromRGB(12, 21, 45)
    controlsFrame.BorderSizePixel = 0
    controlsFrame.Parent = RealisticSpawnerGuiFrame
    Instance.new("UICorner", controlsFrame).CornerRadius = UDim.new(0, 10)

    local minBox = Instance.new("TextBox")
    minBox.Size = UDim2.new(0.5, -12, 0, 28)
    minBox.Position = UDim2.new(0, 8, 0, 7)
    minBox.BackgroundColor3 = Color3.fromRGB(15, 25, 52)
    minBox.BorderSizePixel = 0
    minBox.PlaceholderText = "Minimum"
    minBox.PlaceholderColor3 = Color3.fromRGB(120, 151, 191)
    minBox.Text = "1"
    minBox.TextColor3 = Color3.fromRGB(220, 240, 255)
    minBox.Font = Enum.Font.Gotham
    minBox.TextSize = 13
    minBox.ClearTextOnFocus = false
    minBox.Parent = controlsFrame
    Instance.new("UICorner", minBox).CornerRadius = UDim.new(0, 7)

    local maxBox = Instance.new("TextBox")
    maxBox.Size = UDim2.new(0.5, -12, 0, 28)
    maxBox.Position = UDim2.new(0.5, 4, 0, 7)
    maxBox.BackgroundColor3 = Color3.fromRGB(15, 25, 52)
    maxBox.BorderSizePixel = 0
    maxBox.PlaceholderText = "Maximum"
    maxBox.PlaceholderColor3 = Color3.fromRGB(120, 151, 191)
    maxBox.Text = "10"
    maxBox.TextColor3 = Color3.fromRGB(220, 240, 255)
    maxBox.Font = Enum.Font.Gotham
    maxBox.TextSize = 13
    maxBox.ClearTextOnFocus = false
    maxBox.Parent = controlsFrame
    Instance.new("UICorner", maxBox).CornerRadius = UDim.new(0, 7)

    local spawnSelectedBtn = Instance.new("TextButton")
    spawnSelectedBtn.Size = UDim2.new(1, -16, 0, 25)
    spawnSelectedBtn.Position = UDim2.new(0, 8, 0, 39)
    spawnSelectedBtn.BackgroundColor3 = BUTTON_COLOR
    spawnSelectedBtn.Text = "SPAWN SELECTED"
    spawnSelectedBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    spawnSelectedBtn.Font = Enum.Font.GothamBold
    spawnSelectedBtn.TextSize = 13
    spawnSelectedBtn.Parent = controlsFrame
    Instance.new("UICorner", spawnSelectedBtn).CornerRadius = UDim.new(0, 7)

    local function getRealisticRange()
        local minAmount = math.floor(tonumber(minBox.Text) or 1)
        local maxAmount = math.floor(tonumber(maxBox.Text) or minAmount)

        minAmount = math.clamp(minAmount, 1, MAX_WEAPON_AMOUNT)
        maxAmount = math.clamp(maxAmount, 1, MAX_WEAPON_AMOUNT)

        if maxAmount < minAmount then
            minAmount, maxAmount = maxAmount, minAmount
        end

        minBox.Text = tostring(minAmount)
        maxBox.Text = tostring(maxAmount)
        return minAmount, maxAmount
    end

    local function setRealisticCardSelected(container, selected)
        container:SetAttribute("Selected", selected)
        container.BackgroundColor3 = selected and Color3.fromRGB(35, 130, 65) or Color3.fromRGB(45, 20, 75)

        if selected then
            task.defer(function()
                if container.Parent and container:GetAttribute("Selected") then
                    container.BackgroundColor3 = Color3.fromRGB(35, 130, 65)
                end
            end)
        end
    end

    local function addRealisticWeaponBox(itemId, itemType, weaponName, rarity)
        local rarityColor = getRarityColor(rarity)
        local itemData = sync[itemType] and sync[itemType][itemId]
        local key = tostring(itemType) .. ":" .. tostring(itemId)

        local container = Instance.new("TextButton")
        container.Name = tostring(itemId)
        container.Size = UDim2.fromOffset(SPAWNER_BOX_SIZE, SPAWNER_BOX_SIZE + SPAWNER_NAME_HEIGHT + SPAWNER_RARITY_HEIGHT)
        container.BackgroundColor3 = Color3.fromRGB(45, 20, 75)
        container.BorderSizePixel = 0
        container.Text = ""
        container.AutoButtonColor = false
        container:SetAttribute("SearchText", (tostring(weaponName or "") .. " " .. tostring(itemId) .. " " .. tostring(rarity or "") .. " " .. tostring(itemType)):lower())
        container:SetAttribute("Selected", false)
        container.Parent = realisticScrollFrame
        Instance.new("UICorner", container).CornerRadius = UDim.new(0, 8)

        local stroke = Instance.new("UIStroke")
        stroke.Color = rarityColor
        stroke.Thickness = 2
        stroke.Transparency = 0.05
        stroke.Parent = container

        local thumbnail = Instance.new("ImageLabel")
        thumbnail.Size = UDim2.new(1, -8, 0, 70)
        thumbnail.Position = UDim2.new(0, 4, 0, 4)
        thumbnail.BackgroundColor3 = Color3.fromRGB(25, 10, 45)
        thumbnail.BorderSizePixel = 0
        thumbnail.Image = getSpawnerThumbnail(itemId, itemData)
        thumbnail.ScaleType = Enum.ScaleType.Fit
        thumbnail.Parent = container
        Instance.new("UICorner", thumbnail).CornerRadius = UDim.new(0, 6)

        local rarityLabel = Instance.new("TextLabel")
        rarityLabel.Size = UDim2.new(1, -4, 0, SPAWNER_RARITY_HEIGHT)
        rarityLabel.Position = UDim2.new(0, 2, 0, 75)
        rarityLabel.BackgroundTransparency = 1
        rarityLabel.Text = rarity or "Unknown"
        rarityLabel.TextColor3 = rarityColor
        rarityLabel.Font = Enum.Font.GothamBold
        rarityLabel.TextSize = 13
        rarityLabel.TextTruncate = Enum.TextTruncate.AtEnd
        rarityLabel.Parent = container

        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(1, -4, 0, SPAWNER_NAME_HEIGHT)
        nameLabel.Position = UDim2.new(0, 2, 0, 94)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = weaponName or itemId
        nameLabel.TextColor3 = Color3.fromRGB(210, 245, 255)
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextSize = 12
        nameLabel.TextWrapped = false
        nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
        nameLabel.Parent = container

        Runtime.connect(container.MouseButton1Click, function()
            if selectedRealisticWeapons[key] then
                selectedRealisticWeapons[key] = nil
                setRealisticCardSelected(container, false)
            else
                selectedRealisticWeapons[key] = {
                    itemId = itemId,
                    itemType = itemType,
                    name = weaponName or itemId,
                }
                setRealisticCardSelected(container, true)
            end
        end)

        Runtime.connect(container.MouseEnter, function()
            if not container:GetAttribute("Selected") then
                TweenService:Create(container, TweenInfo.new(0.15), {
                    BackgroundColor3 = rarityColor:Lerp(Color3.fromRGB(20, 10, 35), 0.45),
                }):Play()
            else
                container.BackgroundColor3 = Color3.fromRGB(35, 130, 65)
            end
        end)

        Runtime.connect(container.MouseLeave, function()
            if not container:GetAttribute("Selected") then
                TweenService:Create(container, TweenInfo.new(0.15), {
                    BackgroundColor3 = Color3.fromRGB(45, 20, 75),
                }):Play()
            else
                container.BackgroundColor3 = Color3.fromRGB(35, 130, 65)
            end
        end)
    end

    populateRealisticSpawner = function()
        if didPopulateRealisticSpawner then
            return
        end

        didPopulateRealisticSpawner = true

        local weapons = {}
        local seen = {}

        local function collect(container, itemType)
            for itemId, data in pairs(container or {}) do
                if type(data) == "table" and isSpawnerRarity(data) and not seen[itemId] then
                    seen[itemId] = true

                    table.insert(weapons, {
                        itemId = itemId,
                        itemType = itemType,
                        name = data.ItemName or data.Name or itemId,
                        rarity = data.Rarity or "Unknown",
                    })
                end
            end
        end

        collect(sync.Weapons, "Weapons")
        collect(sync.Item, "Item")

        table.sort(weapons, function(a, b)
            if a.rarity == b.rarity then
                return a.name < b.name
            end

            if a.rarity == "Ancient" and b.rarity ~= "Ancient" then
                return true
            end

            return false
        end)

        for index, weapon in ipairs(weapons) do
            addRealisticWeaponBox(weapon.itemId, weapon.itemType, weapon.name, weapon.rarity)
            local child = realisticScrollFrame:FindFirstChild(tostring(weapon.itemId))
            if child then
                child.LayoutOrder = index
            end
        end

        filterSpawnerCards(realisticScrollFrame, realisticSearchBox.Text)
    end

    Runtime.connect(realisticSearchBox:GetPropertyChangedSignal("Text"), function()
        filterSpawnerCards(realisticScrollFrame, realisticSearchBox.Text)
    end)

    Runtime.connect(spawnSelectedBtn.MouseButton1Click, function()
        local minAmount, maxAmount = getRealisticRange()
        local spawnedCount = 0
        local selectedCount = 0

        for _, weapon in pairs(selectedRealisticWeapons) do
            selectedCount += 1
            local amount = math.random(minAmount, maxAmount)
            if spawnWeaponByIdNoPopup(weapon.itemId, weapon.itemType, amount) then
                spawnedCount += 1
            end
        end

        if selectedCount < 1 then
            spawnSelectedBtn.Text = "SELECT WEAPONS FIRST"
        else
            spawnSelectedBtn.Text = "SPAWNED " .. spawnedCount .. " TYPES"
        end

        task.delay(2, function()
            spawnSelectedBtn.Text = "SPAWN SELECTED"
        end)
    end)
end

local function AddWeaponBox(itemId, itemType, weaponName, rarity)
    local rarityColor = getRarityColor(rarity)
    local itemData = sync[itemType] and sync[itemType][itemId]

    local container = Instance.new("TextButton")
    container.Name = tostring(itemId)
    container.Size = UDim2.fromOffset(SPAWNER_BOX_SIZE, SPAWNER_BOX_SIZE + SPAWNER_NAME_HEIGHT + SPAWNER_RARITY_HEIGHT)
    container.BackgroundColor3 = Color3.fromRGB(45, 20, 75)
    container.BorderSizePixel = 0
    container.Text = ""
    container.AutoButtonColor = false
    container:SetAttribute("SearchText", (tostring(weaponName or "") .. " " .. tostring(itemId) .. " " .. tostring(rarity or "") .. " " .. tostring(itemType)):lower())
    container.Parent = WeaponScrollFrame
    Instance.new("UICorner", container).CornerRadius = UDim.new(0, 8)

    local stroke = Instance.new("UIStroke")
    stroke.Color = rarityColor
    stroke.Thickness = 2
    stroke.Transparency = 0.05
    stroke.Parent = container

    local thumbnail = Instance.new("ImageLabel")
    thumbnail.Size = UDim2.new(1, -8, 0, 70)
    thumbnail.Position = UDim2.new(0, 4, 0, 4)
    thumbnail.BackgroundColor3 = Color3.fromRGB(25, 10, 45)
    thumbnail.BorderSizePixel = 0
    thumbnail.Image = getSpawnerThumbnail(itemId, itemData)
    thumbnail.ScaleType = Enum.ScaleType.Fit
    thumbnail.Parent = container
    Instance.new("UICorner", thumbnail).CornerRadius = UDim.new(0, 6)

    local rarityLabel = Instance.new("TextLabel")
    rarityLabel.Size = UDim2.new(1, -4, 0, SPAWNER_RARITY_HEIGHT)
    rarityLabel.Position = UDim2.new(0, 2, 0, 75)
    rarityLabel.BackgroundTransparency = 1
    rarityLabel.Text = rarity or "Unknown"
    rarityLabel.TextColor3 = rarityColor
    rarityLabel.Font = Enum.Font.GothamBold
    rarityLabel.TextSize = 13
    rarityLabel.TextTruncate = Enum.TextTruncate.AtEnd
    rarityLabel.Parent = container

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, -4, 0, SPAWNER_NAME_HEIGHT)
    nameLabel.Position = UDim2.new(0, 2, 0, 94)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = weaponName or itemId
    nameLabel.TextColor3 = Color3.fromRGB(210, 245, 255)
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 12
    nameLabel.TextWrapped = false
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.Parent = container

    Runtime.connect(container.MouseButton1Click, function()
        spawnWeaponById(itemId, itemType, currentWeaponAmount)
    end)

    Runtime.connect(container.MouseEnter, function()
        TweenService:Create(container, TweenInfo.new(0.15), {
            BackgroundColor3 = rarityColor:Lerp(Color3.fromRGB(20, 10, 35), 0.45),
        }):Play()
    end)

    Runtime.connect(container.MouseLeave, function()
        TweenService:Create(container, TweenInfo.new(0.15), {
            BackgroundColor3 = Color3.fromRGB(45, 20, 75),
        }):Play()
    end)
end

local function AddOfferWeaponBox(itemId, itemType, weaponName, rarity)
    local rarityColor = getRarityColor(rarity)
    local itemData = sync[itemType] and sync[itemType][itemId]

    local container = Instance.new("TextButton")
    container.Name = tostring(itemId)
    container.Size = UDim2.fromOffset(SPAWNER_BOX_SIZE, SPAWNER_BOX_SIZE + SPAWNER_NAME_HEIGHT + SPAWNER_RARITY_HEIGHT)
    container.BackgroundColor3 = Color3.fromRGB(45, 20, 75)
    container.BorderSizePixel = 0
    container.Text = ""
    container.AutoButtonColor = false
    container:SetAttribute("SearchText", (tostring(weaponName or "") .. " " .. tostring(itemId) .. " " .. tostring(rarity or "") .. " " .. tostring(itemType)):lower())
    container.Parent = OfferWeaponScrollFrame
    Instance.new("UICorner", container).CornerRadius = UDim.new(0, 8)

    local stroke = Instance.new("UIStroke")
    stroke.Color = rarityColor
    stroke.Thickness = 2
    stroke.Transparency = 0.05
    stroke.Parent = container

    local thumbnail = Instance.new("ImageLabel")
    thumbnail.Size = UDim2.new(1, -8, 0, 70)
    thumbnail.Position = UDim2.new(0, 4, 0, 4)
    thumbnail.BackgroundColor3 = Color3.fromRGB(25, 10, 45)
    thumbnail.BorderSizePixel = 0
    thumbnail.Image = getSpawnerThumbnail(itemId, itemData)
    thumbnail.ScaleType = Enum.ScaleType.Fit
    thumbnail.Parent = container
    Instance.new("UICorner", thumbnail).CornerRadius = UDim.new(0, 6)

    local rarityLabel = Instance.new("TextLabel")
    rarityLabel.Size = UDim2.new(1, -4, 0, SPAWNER_RARITY_HEIGHT)
    rarityLabel.Position = UDim2.new(0, 2, 0, 75)
    rarityLabel.BackgroundTransparency = 1
    rarityLabel.Text = rarity or "Unknown"
    rarityLabel.TextColor3 = rarityColor
    rarityLabel.Font = Enum.Font.GothamBold
    rarityLabel.TextSize = 13
    rarityLabel.TextTruncate = Enum.TextTruncate.AtEnd
    rarityLabel.Parent = container

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, -4, 0, SPAWNER_NAME_HEIGHT)
    nameLabel.Position = UDim2.new(0, 2, 0, 94)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = weaponName or itemId
    nameLabel.TextColor3 = Color3.fromRGB(210, 245, 255)
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 12
    nameLabel.TextWrapped = false
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.Parent = container

    Runtime.connect(container.MouseButton1Click, function()
        if addSpecificItemToTheirOffer then
            addSpecificItemToTheirOffer(itemId, itemType)
        end
    end)

    Runtime.connect(container.MouseEnter, function()
        TweenService:Create(container, TweenInfo.new(0.15), {
            BackgroundColor3 = rarityColor:Lerp(Color3.fromRGB(20, 10, 35), 0.45),
        }):Play()
    end)

    Runtime.connect(container.MouseLeave, function()
        TweenService:Create(container, TweenInfo.new(0.15), {
            BackgroundColor3 = Color3.fromRGB(45, 20, 75),
        }):Play()
    end)
end

local didPopulateWeaponSpawner = false
local didPopulateOfferSpawner = false

local function populateWeaponSpawner()
    if didPopulateWeaponSpawner then
        return
    end

    didPopulateWeaponSpawner = true

    local weapons = {}
    local seen = {}

    local function collect(container, itemType)
        for itemId, data in pairs(container or {}) do
            if type(data) == "table" and isSpawnerRarity(data) and not seen[itemId] then
                seen[itemId] = true

                table.insert(weapons, {
                    itemId = itemId,
                    itemType = itemType,
                    name = data.ItemName or data.Name or itemId,
                    rarity = data.Rarity or "Unknown",
                })
            end
        end
    end

    collect(sync.Weapons, "Weapons")
    collect(sync.Item, "Item")

    table.sort(weapons, function(a, b)
        if a.rarity == b.rarity then
            return a.name < b.name
        end

        if a.rarity == "Ancient" and b.rarity ~= "Ancient" then
            return true
        end

        return false
    end)

    for index, weapon in ipairs(weapons) do
        AddWeaponBox(weapon.itemId, weapon.itemType, weapon.name, weapon.rarity)
        local child = WeaponScrollFrame:FindFirstChild(tostring(weapon.itemId))
        if child then
            child.LayoutOrder = index
        end
    end

    filterSpawnerCards(WeaponScrollFrame, WeaponSearchBox.Text)
end

local function populateOfferSpawner()
    if didPopulateOfferSpawner then
        return
    end

    didPopulateOfferSpawner = true

    local weapons = {}
    local seen = {}

    local function collect(container, itemType)
        for itemId, data in pairs(container or {}) do
            if isOfferSpawnerWeapon(data) and canFakeTradeItem(itemId, itemType) and not seen[itemId] then
                seen[itemId] = true

                table.insert(weapons, {
                    itemId = itemId,
                    itemType = itemType,
                    name = data.ItemName or data.Name or itemId,
                    rarity = data.Rarity or "Unknown",
                })
            end
        end
    end

    collect(sync.Weapons, "Weapons")
    collect(sync.Item, "Item")

    table.sort(weapons, function(a, b)
        if a.rarity == b.rarity then
            return a.name < b.name
        end

        if a.rarity == "Ancient" and b.rarity ~= "Ancient" then
            return true
        end

        return false
    end)

    for index, weapon in ipairs(weapons) do
        AddOfferWeaponBox(weapon.itemId, weapon.itemType, weapon.name, weapon.rarity)
        local child = OfferWeaponScrollFrame:FindFirstChild(tostring(weapon.itemId))
        if child then
            child.LayoutOrder = index
        end
    end

    filterSpawnerCards(OfferWeaponScrollFrame, OfferSearchBox.Text)
end

local SpecificWeaponBox = CreateBox(SpawnerFrame, "Spawn Weapon (e.g. Harvester)")
do
    local status = Instance.new("TextLabel")
    status.Name = "WeaponVisualStatus"
    status.Size = UDim2.new(1, 0, 0, 38)
    status.BackgroundTransparency = 1
    status.TextColor3 = Color3.fromRGB(235, 192, 126)
    status.Font = Enum.Font.Gotham
    status.TextSize = 11
    status.TextWrapped = true
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Text = ""
    status.Parent = SpawnerFrame
    Runtime.Visual.StatusLabel = status
    for id, message in pairs(Runtime.Visual.Status) do status.Text = tostring(id) .. ": " .. message end
end
local SpawnSpecificBtn = CreateBtn(SpawnerFrame, "SPAWN WEAPON")

CreateSlider(SpawnerFrame, "Weapon Amount", 1, MAX_WEAPON_AMOUNT, 1, 1, function(val)
    currentWeaponAmount = val
end)

local SpawnGodliesBtn = CreateBtn(SpawnerFrame, "SPAWN ALL GODLIES")
local SpawnChromasBtn = CreateBtn(SpawnerFrame, "SPAWN ALL CHROMAS")
local SpawnAncientsBtn = CreateBtn(SpawnerFrame, "SPAWN ALL ANCIENTS")
local OpenSpawnerGuiBtn = CreateBtn(SpawnerFrame, "OPEN SPAWNER GUI")
local OpenRealisticSpawnerGuiBtn = CreateBtn(SpawnerFrame, "REALISTIC SPAWNER GUI")

Runtime.connect(SpawnSpecificBtn.MouseButton1Click, function()
    local weaponName = SpecificWeaponBox.Text

    if weaponName and weaponName ~= "" then
        local success = spawnWeapon(weaponName, currentWeaponAmount)
        if success then
            SpecificWeaponBox.Text = ""
            SpecificWeaponBox.PlaceholderText = "Spawned. Type another..."
            task.delay(2, function()
                SpecificWeaponBox.PlaceholderText = "Spawn Weapon (e.g. Harvester)"
            end)
        else
            SpecificWeaponBox.PlaceholderText = "Not found. Try again..."
            task.delay(2, function()
                SpecificWeaponBox.PlaceholderText = "Spawn Weapon (e.g. Harvester)"
            end)
        end
    else
        SpecificWeaponBox.PlaceholderText = "Type a weapon name first."
        task.delay(2, function()
            SpecificWeaponBox.PlaceholderText = "Spawn Weapon (e.g. Harvester)"
        end)
    end
end)

Runtime.connect(SpecificWeaponBox.FocusLost, function(enterPressed)
    if enterPressed and SpecificWeaponBox.Text ~= "" then
        spawnWeapon(SpecificWeaponBox.Text, currentWeaponAmount)
    end
end)

Runtime.connect(SpawnGodliesBtn.MouseButton1Click, function()
    local count = spawnAllGodlyWeapons(currentWeaponAmount)
    if count > 0 then
        SpawnGodliesBtn.Text = "SPAWNED " .. count .. " GODLIES"
        task.delay(2, function()
            SpawnGodliesBtn.Text = "SPAWN ALL GODLIES"
        end)
    end
end)

Runtime.connect(SpawnChromasBtn.MouseButton1Click, function()
    local count = spawnAllChromaWeapons(currentWeaponAmount)
    if count > 0 then
        SpawnChromasBtn.Text = "SPAWNED " .. count .. " CHROMAS"
        task.delay(2, function()
            SpawnChromasBtn.Text = "SPAWN ALL CHROMAS"
        end)
    else
        SpawnChromasBtn.Text = "NO CHROMAS FOUND"
        task.delay(2, function()
            SpawnChromasBtn.Text = "SPAWN ALL CHROMAS"
        end)
    end
end)

Runtime.connect(SpawnAncientsBtn.MouseButton1Click, function()
    local count = spawnAllAncientWeapons(currentWeaponAmount)
    if count > 0 then
        SpawnAncientsBtn.Text = "SPAWNED " .. count .. " ANCIENTS"
        task.delay(2, function()
            SpawnAncientsBtn.Text = "SPAWN ALL ANCIENTS"
        end)
    else
        SpawnAncientsBtn.Text = "NO ANCIENTS FOUND"
        task.delay(2, function()
            SpawnAncientsBtn.Text = "SPAWN ALL ANCIENTS"
        end)
    end
end)

Runtime.connect(OpenSpawnerGuiBtn.MouseButton1Click, function()
    populateWeaponSpawner()
    SpawnerGuiFrame.Visible = not SpawnerGuiFrame.Visible
end)

Runtime.connect(OpenRealisticSpawnerGuiBtn.MouseButton1Click, function()
    populateRealisticSpawner()
    RealisticSpawnerGuiFrame.Visible = not RealisticSpawnerGuiFrame.Visible
end)

local StartTradeBtn = CreateBtn(TradeFrame, "START TRADE")
local OfferSpawnerBtn = CreateBtn(TradeFrame, "OFFER SPAWNER")
local AddRandomBtn = CreateBtn(TradeFrame, "ADD RANDOM THEIR GODLY")
local RemoveLastBtn = CreateBtn(TradeFrame, "REMOVE LAST THEIR ITEM")

Runtime.connect(OfferSpawnerBtn.MouseButton1Click, function()
    populateOfferSpawner()
    OfferSpawnerGuiFrame.Visible = not OfferSpawnerGuiFrame.Visible
end)

CartiHubSelectedUpgradePlayerName = nil
CartiHubUpgradePlayerDropdownBtn = CreateBtn(UpgradingFrame, "SELECT PLAYER: NONE")
CartiHubUpgradePlayerListFrame = Instance.new("ScrollingFrame")
CartiHubUpgradePlayerListFrame.Size = UDim2.new(1, 0, 0, 180)
CartiHubUpgradePlayerListFrame.BackgroundColor3 = Color3.fromRGB(12, 21, 45)
CartiHubUpgradePlayerListFrame.BorderSizePixel = 0
CartiHubUpgradePlayerListFrame.ScrollBarThickness = 4
CartiHubUpgradePlayerListFrame.ScrollBarImageColor3 = Color3.fromRGB(83, 220, 255)
CartiHubUpgradePlayerListFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
CartiHubUpgradePlayerListFrame.ClipsDescendants = true
CartiHubUpgradePlayerListFrame.Parent = UpgradingFrame
Instance.new("UICorner", CartiHubUpgradePlayerListFrame).CornerRadius = UDim.new(0, 8)

CartiHubUpgradePlayerListPadding = Instance.new("UIPadding")
CartiHubUpgradePlayerListPadding.PaddingTop = UDim.new(0, 6)
CartiHubUpgradePlayerListPadding.PaddingBottom = UDim.new(0, 6)
CartiHubUpgradePlayerListPadding.PaddingLeft = UDim.new(0, 6)
CartiHubUpgradePlayerListPadding.PaddingRight = UDim.new(0, 6)
CartiHubUpgradePlayerListPadding.Parent = CartiHubUpgradePlayerListFrame

CartiHubUpgradePlayerListLayout = Instance.new("UIListLayout")
CartiHubUpgradePlayerListLayout.SortOrder = Enum.SortOrder.LayoutOrder
CartiHubUpgradePlayerListLayout.Padding = UDim.new(0, 5)
CartiHubUpgradePlayerListLayout.Parent = CartiHubUpgradePlayerListFrame

Runtime.connect(CartiHubUpgradePlayerListLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
    CartiHubUpgradePlayerListFrame.CanvasSize = UDim2.new(
        0,
        0,
        0,
        Runtime.uiCanvasHeight(CartiHubUpgradePlayerListLayout) + 12
    )
end)

CartiHubLaunchUpgradeTradeBtn = CreateBtn(UpgradingFrame, "LAUNCH FAKE TRADE")
CartiHubFakePersonTradeBtn = CreateBtn(UpgradingFrame, "FAKE UPGRADE FAKE PLAYER")
CartiHubPlayerValuesBtn = CreateBtn(UpgradingFrame, "PLAYERS VALUES")
CartiHubBlockValueBtn = CreateBtn(UpgradingFrame, "BLOCK VALUE")

do
local CartiHubBlockLastTradedBtn = CreateBtn(BlockFrame, "BLOCK LAST TRADED USER")
local HttpService = game:GetService("HttpService")

local CARTI_HUB_USERNAME_LOOKUP_URL = "https://users.roblox.com/v1/usernames/users"
local CARTI_HUB_BLOCK_URL = "https://apis.roblox.com/user-blocking-api/v1/users/%d/block-user"
local CARTI_HUB_BLOCKED_USERS_URL = "https://apis.roblox.com/user-blocking-api/v1/users/get-blocked-users?cursor=&count=50"
local CARTI_HUB_FRIEND_REQUESTS_URL = "https://friends.roblox.com/v1/my/friends/requests?limit=100&cursor=%s"
local CARTI_HUB_DECLINE_FRIEND_REQUEST_URL = "https://friends.roblox.com/v1/users/%d/decline-friend-request"
local CARTI_HUB_DECLINE_ALL_FRIEND_REQUESTS_URL = "https://friends.roblox.com/v1/user/friend-requests/decline-all"
local CARTI_HUB_PAL_HAIR_ASSET_ID = 63690008
local CARTI_HUB_REQUEST_BLOCK_HAIR_ASSET_IDS = {
    [63690008] = true, -- Pal Hair
    [1772336109] = true, -- Down to Earth Hair
    [80274239] = true, -- Black Ponytail
    [62724852] = true, -- Chestnut Bun
}

local function CartiHubGetLocalRequestFunction()
    return request
        or http_request
        or (syn and syn.request)
        or (fluxus and fluxus.request)
end

local function CartiHubGetRuntimeBlockCredentials()
    local provider = _G.CartiHubGetBlockCredentials
    if type(provider) ~= "function" then
        return "", "", ""
    end

    local session, tracker, csrfToken = provider()
    return tostring(session or ""), tostring(tracker or ""), tostring(csrfToken or "")
end

local function CartiHubGetResponseHeader(response, headerName)
    local headers = response and (response.Headers or response.headers)
    if type(headers) ~= "table" then
        return nil
    end

    local expected = string.lower(headerName)
    for key, value in pairs(headers) do
        if string.lower(tostring(key)) == expected then
            return value
        end
    end

    return nil
end

local function CartiHubGetResponseStatus(response)
    return tonumber(response and (response.StatusCode or response.status_code)) or 0
end

local function CartiHubGetResponseBody(response)
    return response and (response.Body or response.body) or ""
end

local function CartiHubDirectBlockRobloxUser(requestFunction, username)
    local robloSecurity, eventTracker, configuredCsrfToken = CartiHubGetRuntimeBlockCredentials()
    if robloSecurity == "" then
        return false, "SET SESSION"
    end

    if eventTracker == "" then
        return false, "BROWSER TRACKER MISSING"
    end

    local lookupResponse = requestFunction({
        Url = CARTI_HUB_USERNAME_LOOKUP_URL,
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json",
        },
        Body = HttpService:JSONEncode({
            usernames = { username },
            excludeBannedUsers = false,
        }),
    })

    if CartiHubGetResponseStatus(lookupResponse) < 200
        or CartiHubGetResponseStatus(lookupResponse) >= 300 then
        return false, "USER LOOKUP FAILED"
    end

    local lookupData = HttpService:JSONDecode(CartiHubGetResponseBody(lookupResponse))
    local userData = lookupData and lookupData.data and lookupData.data[1]
    local userId = userData and tonumber(userData.id)
    if not userId then
        return false, "USER NOT FOUND"
    end

    local browserTrackerId = string.match(eventTracker, "[Bb]rowserid=([%d]+)")
    if not browserTrackerId then
        return false, "BROWSER TRACKER INVALID"
    end

    local cookieHeader = ".ROBLOSECURITY=" .. robloSecurity
        .. "; RBXEventTrackerV2=" .. eventTracker
    local blockUrl = string.format(CARTI_HUB_BLOCK_URL, userId)
    local csrfToken = configuredCsrfToken ~= "" and configuredCsrfToken
        or (_G.CartiHubBlockCsrfToken or "")
    if csrfToken == "" then
        local csrfResponse = requestFunction({
            -- CSRF tokens are scoped to Roblox's API domain. Request it from the
            -- exact endpoint that will receive the authenticated block request.
            Url = blockUrl,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json",
                ["Cookie"] = cookieHeader,
                ["Origin"] = "https://www.roblox.com",
                ["Referer"] = "https://www.roblox.com/",
                ["BrowserTrackerId"] = browserTrackerId,
            },
            Body = "{}",
        })

        csrfToken = CartiHubGetResponseHeader(csrfResponse, "x-csrf-token")
        _G.CartiHubBlockCsrfToken = csrfToken
    end

    if not csrfToken or csrfToken == "" then
        return false, "CSRF TOKEN MISSING"
    end

    local blockResponse = requestFunction({
        Url = blockUrl,
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json",
            ["Cookie"] = cookieHeader,
            ["x-csrf-token"] = csrfToken,
            ["Origin"] = "https://www.roblox.com",
            ["Referer"] = "https://www.roblox.com/",
            ["BrowserTrackerId"] = browserTrackerId,
        },
        Body = "{}",
    })

    local statusCode = CartiHubGetResponseStatus(blockResponse)
    local normalizedBlockBody = string.gsub(CartiHubGetResponseBody(blockResponse), "%s+", "")
    -- Roblox returns numeric code 1 when this request is a no-op for an already
    -- blocked account. Verify the authoritative blocked-user list in both cases.
    if (statusCode >= 200 and statusCode < 300)
        or (statusCode == 400 and normalizedBlockBody == "1") then
        local verifyResponse = requestFunction({
            Url = CARTI_HUB_BLOCKED_USERS_URL,
            Method = "GET",
            Headers = {
                ["Cookie"] = cookieHeader,
                ["Origin"] = "https://www.roblox.com",
                ["Referer"] = "https://www.roblox.com/",
                ["BrowserTrackerId"] = browserTrackerId,
            },
        })

        local verifyStatus = CartiHubGetResponseStatus(verifyResponse)
        local verifyBody = CartiHubGetResponseBody(verifyResponse)

        if verifyStatus < 200 or verifyStatus >= 300 then
            return false, "BLOCK VERIFY FAILED"
        end

        local verifyData = HttpService:JSONDecode(verifyBody)
        local blockedData = verifyData and (verifyData.data or verifyData) or {}
        local blockedUsers = blockedData.blockedUserIds or blockedData.blockedUsers or {}

        for _, blockedUser in ipairs(blockedUsers) do
            local blockedUserId = type(blockedUser) == "table"
                and tonumber(blockedUser.blockedUserId or blockedUser.id or blockedUser.userId)
                or tonumber(blockedUser)

            if blockedUserId == userId then
                return true
            end
        end

        return false, "BLOCK NOT CONFIRMED"
    end

    if statusCode == 401 then
        return false, "ROBLOSECURITY REJECTED"
    end

    if statusCode == 403 then
        _G.CartiHubBlockCsrfToken = nil
        return false, "CSRF TOKEN REJECTED"
    end

    if statusCode == 429 then
        return false, "BLOCK RATE LIMITED"
    end

    return false, "BLOCK FAILED"
end

_G.CartiHubBlockUsername = function(username, callback)
    username = tostring(username or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if username == "" then
        if callback then
            callback(false, "INVALID USER")
        end
        return false
    end

    local requestFunction = CartiHubGetLocalRequestFunction()
    if not requestFunction then
        if callback then
            callback(false, "HTTP UNAVAILABLE")
        end
        return false
    end

    local robloSecurity = CartiHubGetRuntimeBlockCredentials()
    if robloSecurity == "" then
        if callback then
            callback(false, "SET SESSION")
        end
        return false
    end

    task.spawn(function()
        local callOk, success, detail = pcall(function()
            return CartiHubDirectBlockRobloxUser(requestFunction, username)
        end)

        if not callOk then
            warn("[Carti Hub] Block request failed: " .. tostring(success))
            if callback then
                callback(false, "BLOCKER OFFLINE")
            end
            return
        end

        if callback then
            callback(success == true, success and "BLOCKED" or tostring(detail or "BLOCK FAILED"))
        end
    end)

    return true
end

local function CartiHubSetBlockLastTradedButtonText(text, duration)
    CartiHubBlockLastTradedBtn.Text = text

    if duration then
        task.delay(duration, function()
            if CartiHubBlockLastTradedBtn and CartiHubBlockLastTradedBtn.Parent then
                CartiHubBlockLastTradedBtn.Text = "BLOCK LAST TRADED USER"
            end
        end)
    end
end

Runtime.connect(CartiHubBlockLastTradedBtn.MouseButton1Click, function()
    local username = CartiHubGetLastTradedPlayerName and CartiHubGetLastTradedPlayerName()
    if not username then
        CartiHubSetBlockLastTradedButtonText("NO LAST TRADED USER", 2)
        return
    end

    local requestFunction = CartiHubGetLocalRequestFunction()
    if not requestFunction then
        CartiHubSetBlockLastTradedButtonText("EXECUTOR HTTP UNAVAILABLE", 2)
        return
    end

    local robloSecurity = CartiHubGetRuntimeBlockCredentials()
    if robloSecurity == "" then
        CartiHubSetBlockLastTradedButtonText("SET ROBLOSECURITY FIRST", 2)
        return
    end

    CartiHubBlockLastTradedBtn.Text = "BLOCKING " .. tostring(username) .. "..."

    task.spawn(function()
        local callOk, success, errorText = pcall(function()
            return CartiHubDirectBlockRobloxUser(requestFunction, username)
        end)

        if not callOk then
            CartiHubSetBlockLastTradedButtonText("BLOCKER OFFLINE", 2)
            warn("[Carti Hub] Direct Roblox block request failed: " .. tostring(success))
            return
        end

        if success then
            CartiHubSetBlockLastTradedButtonText("BLOCKED: " .. tostring(username), 2)
        else
            CartiHubSetBlockLastTradedButtonText(tostring(errorText):upper(), 2)
            warn("[Carti Hub] Roblox block failed: " .. tostring(errorText))
        end
    end)
end)

function CartiHubDeclinePalHairFriendRequests(runGeneration)
    if runGeneration and runGeneration ~= CartiHubAutoDeclinePalHairSequence then
        return true, 0
    end

    local requestFunction = CartiHubGetLocalRequestFunction()
    local robloSecurity, eventTracker, configuredCsrfToken = CartiHubGetRuntimeBlockCredentials()
    if not requestFunction or robloSecurity == "" then
        return false, "HTTP OR SESSION UNAVAILABLE"
    end

    local browserTrackerId = string.match(eventTracker, "[Bb]rowserid=([%d]+)")
    if not browserTrackerId then
        return false, "BROWSER TRACKER INVALID"
    end

    if os.clock() < (_G.CartiHubPalHairNextAllowedAt or 0) then
        return true, 0
    end

    local cookieHeader = ".ROBLOSECURITY=" .. robloSecurity
        .. "; RBXEventTrackerV2=" .. eventTracker
    local declinedCount = 0
    local csrfToken = configuredCsrfToken ~= "" and configuredCsrfToken
        or (_G.CartiHubFriendRequestCsrfToken or "")
    _G.CartiHubPalHairCheckedAt = _G.CartiHubPalHairCheckedAt or {}
    _G.CartiHubPalHairPendingUsers = _G.CartiHubPalHairPendingUsers or {}
    local cursor = ""
    local pagesChecked = 0

    while pagesChecked < 10 do
        if runGeneration and runGeneration ~= CartiHubAutoDeclinePalHairSequence then
            return true, declinedCount
        end

        local requestList = requestFunction({
            Url = string.format(CARTI_HUB_FRIEND_REQUESTS_URL, HttpService:UrlEncode(cursor)),
            Method = "GET",
            Headers = {
                ["Cookie"] = cookieHeader,
                ["Origin"] = "https://www.roblox.com",
                ["Referer"] = "https://www.roblox.com/",
                ["BrowserTrackerId"] = browserTrackerId,
            },
        })

        local requestListStatus = CartiHubGetResponseStatus(requestList)
        if requestListStatus == 429 then
            local retryAfter = tonumber(CartiHubGetResponseHeader(requestList, "retry-after")) or 15
            _G.CartiHubPalHairNextAllowedAt = os.clock() + math.max(5, retryAfter)
            warn("[Carti Hub] Friend-request API rate limited; resuming in " .. retryAfter .. " seconds.")
            return true, declinedCount
        end

        if requestListStatus < 200 or requestListStatus >= 300 then
            return false, ("REQUEST LIST FAILED (%d): %s"):format(
                requestListStatus,
                string.sub(CartiHubGetResponseBody(requestList), 1, 160)
            )
        end

        local decodeOk, decoded = pcall(HttpService.JSONDecode, HttpService, CartiHubGetResponseBody(requestList))
        if not decodeOk or type(decoded) ~= "table" then
            return false, "REQUEST LIST INVALID"
        end

        for _, entry in ipairs(decoded.data or {}) do
            if runGeneration and runGeneration ~= CartiHubAutoDeclinePalHairSequence then
                return true, declinedCount
            end

            local requesterId = tonumber(entry.id or entry.userId or entry.requesterId
                or (entry.requester and entry.requester.id))

            if requesterId
                and os.clock() - (_G.CartiHubPalHairCheckedAt[requesterId] or 0) >= 300 then
                local wearingOk, wearingData = pcall(function()
                    return Players:GetCharacterAppearanceInfoAsync(requesterId)
                end)
                local hasPalHair = false

                if wearingOk and type(wearingData) == "table"
                    and type(wearingData.assets) == "table" then
                    for _, assetData in ipairs(wearingData.assets) do
                        if tonumber(assetData.id) == CARTI_HUB_PAL_HAIR_ASSET_ID then
                            hasPalHair = true
                            break
                        end
                    end
                elseif not wearingOk then
                    warn("[Carti Hub] Appearance lookup failed for user " .. requesterId .. ": " .. tostring(wearingData))
                end

                if hasPalHair then
                    local now = os.clock()
                    local pendingUsers = _G.CartiHubPalHairPendingUsers
                    pendingUsers[requesterId] = pendingUsers[requesterId] or now

                    local recentCount = 0
                    for userId, detectedAt in pairs(pendingUsers) do
                        if now - detectedAt <= 5 then
                            recentCount += 1
                        else
                            pendingUsers[userId] = nil
                        end
                    end

                    if recentCount > 5 then
                        local declineAllUrl = CARTI_HUB_DECLINE_ALL_FRIEND_REQUESTS_URL

                        if csrfToken == "" then
                            local csrfResponse = requestFunction({
                                Url = declineAllUrl,
                                Method = "POST",
                                Headers = {
                                    ["Content-Type"] = "application/json",
                                    ["Cookie"] = cookieHeader,
                                    ["Origin"] = "https://www.roblox.com",
                                    ["Referer"] = "https://www.roblox.com/",
                                    ["BrowserTrackerId"] = browserTrackerId,
                                },
                                Body = "{}",
                            })
                            csrfToken = CartiHubGetResponseHeader(csrfResponse, "x-csrf-token") or ""
                            _G.CartiHubFriendRequestCsrfToken = csrfToken
                        end

                        if csrfToken ~= "" then
                            local declineAllResponse = requestFunction({
                                Url = declineAllUrl,
                                Method = "POST",
                                Headers = {
                                    ["Content-Type"] = "application/json",
                                    ["Cookie"] = cookieHeader,
                                    ["x-csrf-token"] = csrfToken,
                                    ["Origin"] = "https://www.roblox.com",
                                    ["Referer"] = "https://www.roblox.com/",
                                    ["BrowserTrackerId"] = browserTrackerId,
                                },
                                Body = "{}",
                            })
                            local declineAllStatus = CartiHubGetResponseStatus(declineAllResponse)

                            if declineAllStatus >= 200 and declineAllStatus < 300 then
                                table.clear(pendingUsers)
                                table.clear(_G.CartiHubPalHairCheckedAt)
                                return true, recentCount
                            elseif declineAllStatus == 429 then
                                local retryAfter = tonumber(CartiHubGetResponseHeader(declineAllResponse, "retry-after")) or 15
                                _G.CartiHubPalHairNextAllowedAt = os.clock() + math.max(5, retryAfter)
                                return true, 0
                            end
                        end
                    elseif now - pendingUsers[requesterId] < 5 then
                        hasPalHair = false
                    end
                end

                if hasPalHair then
                    local declineUrl = string.format(CARTI_HUB_DECLINE_FRIEND_REQUEST_URL, requesterId)

                    if csrfToken == "" then
                        local csrfResponse = requestFunction({
                            Url = declineUrl,
                            Method = "POST",
                            Headers = {
                                ["Content-Type"] = "application/json",
                                ["Cookie"] = cookieHeader,
                                ["Origin"] = "https://www.roblox.com",
                                ["Referer"] = "https://www.roblox.com/",
                                ["BrowserTrackerId"] = browserTrackerId,
                            },
                            Body = "{}",
                        })
                        csrfToken = CartiHubGetResponseHeader(csrfResponse, "x-csrf-token") or ""
                        _G.CartiHubFriendRequestCsrfToken = csrfToken
                    end

                    if csrfToken ~= "" then
                        local declineResponse = requestFunction({
                            Url = declineUrl,
                            Method = "POST",
                            Headers = {
                                ["Content-Type"] = "application/json",
                                ["Cookie"] = cookieHeader,
                                ["x-csrf-token"] = csrfToken,
                                ["Origin"] = "https://www.roblox.com",
                                ["Referer"] = "https://www.roblox.com/",
                                ["BrowserTrackerId"] = browserTrackerId,
                            },
                            Body = "{}",
                        })

                        local declineStatus = CartiHubGetResponseStatus(declineResponse)
                        if declineStatus >= 200 and declineStatus < 300 then
                            declinedCount += 1
                            _G.CartiHubPalHairCheckedAt[requesterId] = os.clock()
                            _G.CartiHubPalHairPendingUsers[requesterId] = nil
                            task.wait(2)
                        elseif declineStatus == 403 then
                            csrfToken = ""
                            _G.CartiHubFriendRequestCsrfToken = nil
                        elseif declineStatus == 429 then
                            local retryAfter = tonumber(CartiHubGetResponseHeader(declineResponse, "retry-after")) or 15
                            _G.CartiHubPalHairNextAllowedAt = os.clock() + math.max(5, retryAfter)
                            warn("[Carti Hub] Friend-request API rate limited; resuming in " .. retryAfter .. " seconds.")
                            return true, declinedCount
                        else
                            warn(("[Carti Hub] Decline failed for %d: status=%d body=%s"):format(
                                requesterId,
                                declineStatus,
                                string.sub(CartiHubGetResponseBody(declineResponse), 1, 160)
                            ))
                        end
                    end
                elseif wearingOk and type(wearingData) == "table" then
                    _G.CartiHubPalHairCheckedAt[requesterId] = os.clock()
                end

                task.wait(0.15)
            end
        end

        pagesChecked += 1
        cursor = decoded.nextPageCursor or ""
        if cursor == "" then
            break
        end
    end

    return true, declinedCount
end

function CartiHubBlockUsersFromFriendRequests()
    local requestFunction = CartiHubGetLocalRequestFunction()
    local robloSecurity, eventTracker = CartiHubGetRuntimeBlockCredentials()
    if not requestFunction or robloSecurity == "" then
        return false, "HTTP OR SESSION UNAVAILABLE"
    end

    local browserTrackerId = string.match(eventTracker, "[Bb]rowserid=([%d]+)")
    if not browserTrackerId then
        return false, "BROWSER TRACKER INVALID"
    end

    local cookieHeader = ".ROBLOSECURITY=" .. robloSecurity
        .. "; RBXEventTrackerV2=" .. eventTracker
    local cursor = ""
    local blockedCount = 0
    local seenUsers = {}

    for _ = 1, 10 do
        local response = requestFunction({
            Url = string.format(CARTI_HUB_FRIEND_REQUESTS_URL, HttpService:UrlEncode(cursor)),
            Method = "GET",
            Headers = {
                ["Cookie"] = cookieHeader,
                ["Origin"] = "https://www.roblox.com",
                ["Referer"] = "https://www.roblox.com/",
                ["BrowserTrackerId"] = browserTrackerId,
            },
        })

        if CartiHubGetResponseStatus(response) < 200
            or CartiHubGetResponseStatus(response) >= 300 then
            return false, "REQUEST LIST FAILED"
        end

        local decodeOk, data = pcall(HttpService.JSONDecode, HttpService, CartiHubGetResponseBody(response))
        if not decodeOk or type(data) ~= "table" then
            return false, "REQUEST LIST INVALID"
        end

        for _, entry in ipairs(data.data or {}) do
            local userId = tonumber((entry.friendRequest and entry.friendRequest.senderId)
                or entry.id
                or entry.userId
                or entry.requesterId
                or (entry.requester and entry.requester.id))
            local username = entry.name or entry.username or (entry.requester and entry.requester.name)

            if userId and not seenUsers[userId] then
                seenUsers[userId] = true
                local appearanceOk, appearance = pcall(function()
                    return Players:GetCharacterAppearanceInfoAsync(userId)
                end)
                local matchesHair = false

                if appearanceOk and type(appearance) == "table" then
                    for _, assetData in ipairs(appearance.assets or {}) do
                        if CARTI_HUB_REQUEST_BLOCK_HAIR_ASSET_IDS[tonumber(assetData.id)] then
                            matchesHair = true
                            break
                        end
                    end
                end

                if matchesHair then
                    if not username or username == "" then
                        local resolved, resolvedName = pcall(function()
                            return Players:GetNameFromUserIdAsync(userId)
                        end)
                        username = resolved and resolvedName or nil
                    end

                    if username and username ~= "" then
                        local blocked = false
                        local errorText

                        for attempt = 1, 3 do
                            blocked, errorText = CartiHubDirectBlockRobloxUser(requestFunction, username)
                            if blocked or errorText ~= "BLOCK RATE LIMITED" then
                                break
                            end

                            warn("[Carti Hub] Block rate limited; retrying " .. tostring(username) .. " shortly.")
                            task.wait(15)
                        end

                        if blocked then
                            blockedCount += 1
                        else
                            warn("[Carti Hub] Could not block " .. tostring(username) .. ": " .. tostring(errorText))
                        end
                    else
                        warn("[Carti Hub] Could not resolve requested user id " .. tostring(userId))
                    end
                    task.wait(4)
                else
                    task.wait(0.15)
                end
            end
        end

        cursor = data.nextPageCursor or ""
        if cursor == "" then
            break
        end
    end

    return true, blockedCount
end
end

function CartiHubSetSelectedUpgradePlayer(username)
    CartiHubSelectedUpgradePlayerName = username
    CartiHubUpgradePlayerDropdownBtn.Text = username and ("SELECT PLAYER: " .. username) or "SELECT PLAYER: NONE"
end

function CartiHubRefreshUpgradePlayerDropdown()
    if not CartiHubUpgradePlayerListFrame or not CartiHubUpgradePlayerListFrame.Parent then
        return
    end

    local selectedStillHere = CartiHubSelectedUpgradePlayerName == nil

    for _, child in ipairs(CartiHubUpgradePlayerListFrame:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= localPlayer then
            if player.Name == CartiHubSelectedUpgradePlayerName then
                selectedStillHere = true
            end

            local playerButton = Instance.new("TextButton")
            playerButton.Size = UDim2.new(1, 0, 0, 30)
            playerButton.BackgroundColor3 = player.Name == CartiHubSelectedUpgradePlayerName
                and BUTTON_HOVER_COLOR
                or Color3.fromRGB(15, 25, 52)
            playerButton.BorderSizePixel = 0
            playerButton.Text = player.Name
            playerButton.TextColor3 = Color3.fromRGB(220, 240, 255)
            playerButton.Font = Enum.Font.GothamBold
            playerButton.TextSize = 13
            playerButton.Parent = CartiHubUpgradePlayerListFrame
            Instance.new("UICorner", playerButton).CornerRadius = UDim.new(0, 7)

            Runtime.connect(playerButton.MouseButton1Click, function()
                CartiHubSetSelectedUpgradePlayer(player.Name)
                CartiHubRefreshUpgradePlayerDropdown()
            end)
        end
    end

    if not selectedStillHere then
        CartiHubSetSelectedUpgradePlayer(nil)
    end

    CartiHubUpgradePlayerListFrame.CanvasSize = UDim2.new(
        0,
        0,
        0,
        Runtime.uiCanvasHeight(CartiHubUpgradePlayerListLayout) + 12
    )
end

Runtime.connect(CartiHubUpgradePlayerDropdownBtn.MouseButton1Click, CartiHubRefreshUpgradePlayerDropdown)

CartiHubAutoSelectLastTradedEnabled = true
CartiHubAutoSelectLastTradedBtn = CreateBtn(UpgradingFrame, "AUTO SELECT LAST TRADED: ON")

function CartiHubSetAutoSelectLastTraded(enabled)
    CartiHubAutoSelectLastTradedEnabled = enabled == true
    CartiHubAutoSelectLastTradedBtn.Text = CartiHubAutoSelectLastTradedEnabled
        and "AUTO SELECT LAST TRADED: ON"
        or "AUTO SELECT LAST TRADED: OFF"
    CartiHubAutoSelectLastTradedBtn.BackgroundColor3 = CartiHubAutoSelectLastTradedEnabled
        and BUTTON_HOVER_COLOR
        or BUTTON_COLOR

    if CartiHubAutoSelectLastTradedEnabled and _G.CartiHubLastTradedPlayerName then
        CartiHubTryAutoSelectLastTraded(_G.CartiHubLastTradedPlayerName)
    end
end

function CartiHubTryAutoSelectLastTraded(username)
    if not CartiHubAutoSelectLastTradedEnabled or not username then
        return false
    end

    local player = Players:FindFirstChild(username)
    if not player or player == localPlayer then
        return false
    end

    CartiHubSetSelectedUpgradePlayer(player.Name)
    CartiHubRefreshUpgradePlayerDropdown()
    return true
end

Runtime.connect(CartiHubAutoSelectLastTradedBtn.MouseButton1Click, function()
    CartiHubSetAutoSelectLastTraded(not CartiHubAutoSelectLastTradedEnabled)
end)

CartiHubSetAutoSelectLastTraded(true)

Runtime.connect(CartiHubLaunchUpgradeTradeBtn.MouseButton1Click, function()
    if not CartiHubSelectedUpgradePlayerName then
        CartiHubLaunchUpgradeTradeBtn.Text = "SELECT A PLAYER FIRST"
        task.delay(2, function()
            CartiHubLaunchUpgradeTradeBtn.Text = "LAUNCH FAKE TRADE"
        end)
        return
    end

    if CartiHubLaunchUpgradeFakeTrade then
        CartiHubLaunchUpgradeFakeTrade(CartiHubSelectedUpgradePlayerName)
    else
        warn("[Carti Hub] Fake trade launcher is not ready yet.")
    end
end)

Runtime.connect(CartiHubFakePersonTradeBtn.MouseButton1Click, function()
    if CartiHubLaunchFakeUpgradeFakePlayer then
        CartiHubLaunchFakeUpgradeFakePlayer()
    else
        CartiHubFakePersonTradeBtn.Text = "TRADE UI NOT READY"
        task.delay(2, function()
            if CartiHubFakePersonTradeBtn.Parent then
                CartiHubFakePersonTradeBtn.Text = "FAKE UPGRADE FAKE PLAYER"
            end
        end)
    end
end)

Runtime.connect(CartiHubPlayerValuesBtn.MouseButton1Click, function()
    local openValues = _G.CartiHubOpenPlayerValuesGui
    if type(openValues) == "function" then
        openValues()
    else
        CartiHubPlayerValuesBtn.Text = "VALUES UI NOT READY"
        task.delay(2, function()
            if CartiHubPlayerValuesBtn.Parent then
                CartiHubPlayerValuesBtn.Text = "PLAYERS VALUES"
            end
        end)
    end
end)

Runtime.connect(CartiHubBlockValueBtn.MouseButton1Click, function()
    local openBlockValue = _G.CartiHubOpenBlockValueGui
    if type(openBlockValue) == "function" then
        openBlockValue()
    else
        CartiHubBlockValueBtn.Text = "BLOCK VALUE NOT READY"
        task.delay(2, function()
            if CartiHubBlockValueBtn.Parent then
                CartiHubBlockValueBtn.Text = "BLOCK VALUE"
            end
        end)
    end
end)

task.spawn(function()
    while SakaUI and SakaUI.Parent do
        CartiHubRefreshUpgradePlayerDropdown()
        task.wait(2)
    end
end)

do
local AutoTradeBtn = CreateBtn(SettingsFrame, "AUTO TRADE: OFF")

local autoTradeEnabled = false
local autoTradeSequence = 0

if _G.CartiHubAutoTradeState then
    _G.CartiHubAutoTradeState.Enabled = false
end

local autoTradeState = {
    Enabled = false,
}

_G.CartiHubAutoTradeState = autoTradeState
-- Edit this list to control which item names Auto Trade searches for.
_G.CartiHubAutoTradeSearchTerms = {
"Gingerscope",
"Blossom",
"Flora",
"Heart Wand",
"Sakura",
"Sunrise",
"Sunset",
"Sweet",
"Treat",
"Turkey",
"Watergun",
"Celestial",
"Icepiercer",
"Swirly Axe",
"Bauble",
"Blizzard",
"Constellation",
"Evergreen",
"Evergun",
"Swirly Gun",
"Traveler's Axe",
"Bat",
"Raygun",
"Traveler's Gun",
"Vampires's Gun"
}

local function isAutoTradeBusy()
    local gui = tradeModule.GUI
    if not gui then
        return true
    end

    if _G.CartiHubFakeTradeActive then
        return true
    end

    if gui.TradeGUI and gui.TradeGUI.Enabled then
        return true
    end

    return false
end

local function setAutoTradeEnabled(enabled)
    autoTradeEnabled = enabled == true
    autoTradeState.Enabled = autoTradeEnabled
    autoTradeSequence += 1

    local sequence = autoTradeSequence
    AutoTradeBtn.Text = autoTradeEnabled and "AUTO TRADE: ON" or "AUTO TRADE: OFF"
    AutoTradeBtn.BackgroundColor3 = autoTradeEnabled and BUTTON_HOVER_COLOR or BUTTON_COLOR

    if not autoTradeEnabled then
        return
    end

    task.spawn(function()
        while autoTradeEnabled
            and autoTradeState.Enabled
            and sequence == autoTradeSequence
            and SakaUI
            and SakaUI.Parent do
            if not isAutoTradeBusy() then
                local startFakeTrade = _G.CartiHubStartFakeTrade
                if type(startFakeTrade) == "function" then
                    startFakeTrade(true)
                end
            end

            task.wait(math.random(20, 40) / 10)
        end
    end)
end

Runtime.connect(AutoTradeBtn.MouseButton1Click, function()
    setAutoTradeEnabled(not autoTradeEnabled)
end)
end

local friendJoinDelaySeconds = 30
local autoFriendJoinEnabled = false
local autoFriendJoinSequence = 0

CreateSlider(SettingsFrame, "Friend Joined Delay (Sec)", 30, 300, 30, 10, function(val)
    friendJoinDelaySeconds = val
end)

local FriendJoinToggleBtn = CreateBtn(SettingsFrame, "FRIEND JOINED")
local AutoFriendJoinBtn = CreateBtn(SettingsFrame, "AUTO FRIEND JOIN: OFF")
local applyAvatarFromUserId
local AvatarChangerBtn = CreateBtn(SettingsFrame, "AVATAR CHANGER")
CreateBtn(KeybindsFrame, "Toggle UI: 6")
CreateBtn(KeybindsFrame, "Start Trade: Z")
CreateBtn(KeybindsFrame, "Friend Join: F")
CreateBtn(KeybindsFrame, "Random >200 Offer: 2")

do
local avatarPersistenceState = _G.CartiHubAvatarPersistenceState or {
    UserId = nil,
    Connection = nil,
}

if avatarPersistenceState.Connection then
    pcall(function()
        avatarPersistenceState.Connection:Disconnect()
    end)
end

_G.CartiHubAvatarPersistenceState = avatarPersistenceState

local AvatarChangerFrame = Instance.new("Frame")
AvatarChangerFrame.Name = "AvatarChangerGUI"
AvatarChangerFrame.Size = UDim2.new(0, 280, 0, 190)
AvatarChangerFrame.Position = UDim2.new(0.5, -140, 0.5, -95)
AvatarChangerFrame.BackgroundColor3 = Color3.fromRGB(9, 14, 31)
AvatarChangerFrame.BorderSizePixel = 0
AvatarChangerFrame.Active = true
AvatarChangerFrame.Draggable = true
AvatarChangerFrame.Visible = false
AvatarChangerFrame.Parent = SakaUI
Instance.new("UICorner", AvatarChangerFrame).CornerRadius = UDim.new(0, 14)

local AvatarChangerStroke = Instance.new("UIStroke")
AvatarChangerStroke.Color = Color3.fromRGB(83, 220, 255)
AvatarChangerStroke.Thickness = 2
AvatarChangerStroke.Transparency = 0.15
AvatarChangerStroke.Parent = AvatarChangerFrame

local AvatarChangerTitle = Instance.new("TextLabel")
AvatarChangerTitle.Size = UDim2.new(1, -44, 0, 36)
AvatarChangerTitle.Position = UDim2.new(0, 14, 0, 6)
AvatarChangerTitle.BackgroundTransparency = 1
AvatarChangerTitle.Text = "Avatar Changer"
AvatarChangerTitle.TextColor3 = Color3.fromRGB(210, 245, 255)
AvatarChangerTitle.Font = Enum.Font.GothamBold
AvatarChangerTitle.TextSize = 17
AvatarChangerTitle.TextXAlignment = Enum.TextXAlignment.Left
AvatarChangerTitle.Parent = AvatarChangerFrame

local AvatarChangerCloseBtn = Instance.new("TextButton")
AvatarChangerCloseBtn.Size = UDim2.new(0, 30, 0, 30)
AvatarChangerCloseBtn.Position = UDim2.new(1, -38, 0, 7)
AvatarChangerCloseBtn.BackgroundTransparency = 1
AvatarChangerCloseBtn.Text = "X"
AvatarChangerCloseBtn.TextColor3 = Color3.fromRGB(255, 128, 207)
AvatarChangerCloseBtn.Font = Enum.Font.GothamBold
AvatarChangerCloseBtn.TextSize = 18
AvatarChangerCloseBtn.Parent = AvatarChangerFrame

local AvatarUserIdBox = Instance.new("TextBox")
AvatarUserIdBox.Size = UDim2.new(1, -28, 0, 38)
AvatarUserIdBox.Position = UDim2.new(0, 14, 0, 52)
AvatarUserIdBox.BackgroundColor3 = Color3.fromRGB(15, 25, 52)
AvatarUserIdBox.PlaceholderText = "Username or User ID"
AvatarUserIdBox.PlaceholderColor3 = Color3.fromRGB(120, 151, 191)
AvatarUserIdBox.Text = ""
AvatarUserIdBox.TextColor3 = Color3.fromRGB(220, 240, 255)
AvatarUserIdBox.Font = Enum.Font.Gotham
AvatarUserIdBox.TextSize = 14
AvatarUserIdBox.ClearTextOnFocus = false
AvatarUserIdBox.Parent = AvatarChangerFrame
Instance.new("UICorner", AvatarUserIdBox).CornerRadius = UDim.new(0, 8)

local AvatarChangeBtn = Instance.new("TextButton")
AvatarChangeBtn.Size = UDim2.new(1, -28, 0, 38)
AvatarChangeBtn.Position = UDim2.new(0, 14, 0, 102)
AvatarChangeBtn.BackgroundColor3 = BUTTON_COLOR
AvatarChangeBtn.Text = "CHANGE AVATAR"
AvatarChangeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
AvatarChangeBtn.Font = Enum.Font.GothamBold
AvatarChangeBtn.TextSize = 13
AvatarChangeBtn.Parent = AvatarChangerFrame
Instance.new("UICorner", AvatarChangeBtn).CornerRadius = UDim.new(0, 8)

local AvatarResetBtn = Instance.new("TextButton")
AvatarResetBtn.Size = UDim2.new(1, -28, 0, 34)
AvatarResetBtn.Position = UDim2.new(0, 14, 0, 146)
AvatarResetBtn.BackgroundColor3 = Color3.fromRGB(110, 70, 210)
AvatarResetBtn.Text = "RESET AVATAR"
AvatarResetBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
AvatarResetBtn.Font = Enum.Font.GothamBold
AvatarResetBtn.TextSize = 13
AvatarResetBtn.Parent = AvatarChangerFrame
Instance.new("UICorner", AvatarResetBtn).CornerRadius = UDim.new(0, 8)

local function setAvatarButtonText(button, text)
    button.Text = text
    task.delay(2, function()
        if button == AvatarChangeBtn then
            button.Text = "CHANGE AVATAR"
        elseif button == AvatarResetBtn then
            button.Text = "RESET AVATAR"
        end
    end)
end

local function resolveAvatarUserId(input)
    input = tostring(input or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if input == "" then
        return nil, "TYPE USERNAME OR ID"
    end

    local livePlayer = Players:FindFirstChild(input)
    if livePlayer then
        return livePlayer.UserId, nil, livePlayer
    end

    local numericUserId = tonumber(input)
    if numericUserId and numericUserId >= 1 then
        for _, player in ipairs(Players:GetPlayers()) do
            if player.UserId == numericUserId then
                return numericUserId, nil, player
            end
        end

        return numericUserId
    end

    local ok, resolvedUserId = pcall(function()
        return Players:GetUserIdFromNameAsync(input)
    end)

    if not ok or not resolvedUserId then
        return nil, "USER NOT FOUND"
    end

    return resolvedUserId
end

local function clearLocalAvatarAppearance(character)
    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("Accessory")
            or child:IsA("Accoutrement")
            or child:IsA("Shirt")
            or child:IsA("Pants")
            or child:IsA("ShirtGraphic")
            or child:IsA("BodyColors")
            or child:IsA("CharacterMesh") then
            child:Destroy()
        end
    end

    local head = character:FindFirstChild("Head")
    if head then
        for _, child in ipairs(head:GetChildren()) do
            if child:IsA("Decal") and child.Name == "face" then
                child:Destroy()
            end
        end
    end
end

local function findCharacterAttachment(character, attachmentName)
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("Attachment") and descendant.Name == attachmentName then
            return descendant
        end
    end

    return nil
end

local function weldAccessoryToCharacter(accessory, character)
    local handle = accessory:FindFirstChild("Handle")
    if not handle or not handle:IsA("BasePart") then
        return false
    end

    handle.Anchored = false
    handle.CanCollide = false
    handle.Massless = true

    local handleAttachment = handle:FindFirstChildOfClass("Attachment")
    local characterAttachment = handleAttachment and findCharacterAttachment(character, handleAttachment.Name)
    local targetPart = characterAttachment and characterAttachment.Parent

    if not handleAttachment or not characterAttachment or not targetPart or not targetPart:IsA("BasePart") then
        targetPart = character:FindFirstChild("Head")
        if not targetPart or not targetPart:IsA("BasePart") then
            return false
        end
    end

    local weld = handle:FindFirstChild("AccessoryWeld")
    if not weld then
        weld = Instance.new("Weld")
        weld.Name = "AccessoryWeld"
        weld.Parent = handle
    end

    weld.Part0 = handle
    weld.Part1 = targetPart

    if handleAttachment and characterAttachment then
        weld.C0 = handleAttachment.CFrame
        weld.C1 = characterAttachment.CFrame
    else
        local ok, attachmentPoint = pcall(function()
            return accessory.AttachmentPoint
        end)

        weld.C0 = CFrame.new()
        weld.C1 = ok and attachmentPoint or CFrame.new(0, 0.5, 0)
        handle.CFrame = targetPart.CFrame * weld.C1 * weld.C0:Inverse()
    end

    return true
end

local function addAvatarAccessory(character, humanoid, sourceAccessory)
    local accessory = sourceAccessory:Clone()
    accessory.Parent = character
    weldAccessoryToCharacter(accessory, character)
end

local function applyBodyDescriptionValues(humanoid, description)
    if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
        return
    end

    local scaleMap = {
        BodyDepthScale = { "DepthScale", "BodyDepthScale" },
        BodyHeightScale = { "HeightScale", "BodyHeightScale" },
        BodyProportionScale = { "ProportionScale", "BodyProportionScale" },
        BodyTypeScale = { "BodyTypeScale" },
        BodyWidthScale = { "WidthScale", "BodyWidthScale" },
        HeadScale = { "HeadScale" },
    }

    for humanoidScaleName, descriptionNames in pairs(scaleMap) do
        local valueObject = humanoid:FindFirstChild(humanoidScaleName)
        if valueObject and valueObject:IsA("NumberValue") then
            for _, descriptionName in ipairs(descriptionNames) do
                local ok, sourceValue = pcall(function()
                    return description[descriptionName]
                end)

                if ok and typeof(sourceValue) == "number" then
                    valueObject.Value = sourceValue
                    break
                end
            end
        end
    end
end

local function copyHeadFace(sourceModel, character)
    local sourceHead = sourceModel:FindFirstChild("Head")
    local targetHead = character:FindFirstChild("Head")
    if not sourceHead or not targetHead then
        return
    end

    for _, child in ipairs(targetHead:GetChildren()) do
        if child:IsA("Decal") or child:IsA("Texture") then
            child:Destroy()
        end
    end

    for _, child in ipairs(sourceHead:GetChildren()) do
        if child:IsA("Decal") or child:IsA("Texture") then
            child:Clone().Parent = targetHead
        end
    end
end

local function replaceR15BodyPartsFromModel(sourceModel, character)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local sourceHumanoid = sourceModel:FindFirstChildOfClass("Humanoid")

    if not humanoid
        or not sourceHumanoid
        or humanoid.RigType ~= Enum.HumanoidRigType.R15
        or sourceHumanoid.RigType ~= Enum.HumanoidRigType.R15 then
        return
    end

    local bodyPartMap = {
        Head = Enum.BodyPartR15.Head,
        UpperTorso = Enum.BodyPartR15.UpperTorso,
        LowerTorso = Enum.BodyPartR15.LowerTorso,
        LeftUpperArm = Enum.BodyPartR15.LeftUpperArm,
        LeftLowerArm = Enum.BodyPartR15.LeftLowerArm,
        LeftHand = Enum.BodyPartR15.LeftHand,
        RightUpperArm = Enum.BodyPartR15.RightUpperArm,
        RightLowerArm = Enum.BodyPartR15.RightLowerArm,
        RightHand = Enum.BodyPartR15.RightHand,
        LeftUpperLeg = Enum.BodyPartR15.LeftUpperLeg,
        LeftLowerLeg = Enum.BodyPartR15.LeftLowerLeg,
        LeftFoot = Enum.BodyPartR15.LeftFoot,
        RightUpperLeg = Enum.BodyPartR15.RightUpperLeg,
        RightLowerLeg = Enum.BodyPartR15.RightLowerLeg,
        RightFoot = Enum.BodyPartR15.RightFoot,
    }

    for partName, bodyPartEnum in pairs(bodyPartMap) do
        local sourcePart = sourceModel:FindFirstChild(partName)
        if sourcePart and sourcePart:IsA("BasePart") then
            local replacement = sourcePart:Clone()
            replacement.Name = partName
            replacement.Anchored = false
            replacement.CanCollide = false
            replacement.Massless = false

            pcall(function()
                humanoid:ReplaceBodyPartR15(bodyPartEnum, replacement)
            end)
        end
    end
end

local function copyAvatarModelAppearance(sourceModel, character)
    clearLocalAvatarAppearance(character)

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    replaceR15BodyPartsFromModel(sourceModel, character)

    for _, child in ipairs(sourceModel:GetDescendants()) do
        if child:IsA("BodyColors")
            or child:IsA("Shirt")
            or child:IsA("Pants")
            or child:IsA("ShirtGraphic") then
            child:Clone().Parent = character
        elseif child:IsA("CharacterMesh") and humanoid and humanoid.RigType == Enum.HumanoidRigType.R6 then
            child:Clone().Parent = character
        elseif child:IsA("Accessory") or child:IsA("Accoutrement") then
            addAvatarAccessory(character, humanoid, child)
        elseif child:IsA("BasePart") then
            local targetPart = character:FindFirstChild(child.Name)
            if targetPart
                and targetPart:IsA("BasePart")
                and not targetPart:IsA("MeshPart")
                and not child:IsA("MeshPart") then
                targetPart.Color = child.Color
                targetPart.Material = child.Material
            end
        end
    end

    copyHeadFace(sourceModel, character)

    return true
end

local function applyAvatarByGeneratedModel(userId, character)
    local ok, sourceModel = pcall(function()
        return Players:CreateHumanoidModelFromUserId(userId)
    end)

    if not ok or not sourceModel then
        return false, "MODEL FETCH FAILED"
    end

    sourceModel.Parent = nil
    if not Runtime.Active or character ~= localPlayer.Character then
        sourceModel:Destroy()
        return false, 'CHARACTER CHANGED'
    end

    local copyOk, copyErr = pcall(function()
        copyAvatarModelAppearance(sourceModel, character)
    end)

    sourceModel:Destroy()

    if not copyOk then
        warn("[Carti Hub] Avatar model copy failed: " .. tostring(copyErr))
        return false, "COPY FAILED"
    end

    return true
end

applyAvatarFromUserId = function(userIdOrName)
    if not Runtime.Active then return false, 'HUB CLOSED' end
    if localPlayer.Character and Runtime.AvatarWeapons:IsChanging(localPlayer.Character) then return false, 'AVATAR CHANGE IN PROGRESS' end
    Runtime.AvatarRequestGeneration = (Runtime.AvatarRequestGeneration or 0) + 1
    local generation = Runtime.AvatarRequestGeneration
    local userId, resolveError = resolveAvatarUserId(userIdOrName)
    if not userId then
        return false, resolveError or "INVALID USER"
    end

    local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not humanoid then
        return false, "NO HUMANOID"
    end

    local ok, description = pcall(function()
        return Players:GetHumanoidDescriptionFromUserId(userId)
    end)

    if not ok or not description then
        return false, "USER NOT FOUND"
    end
    if not Runtime.Active or character ~= localPlayer.Character or generation ~= Runtime.AvatarRequestGeneration then
        description:Destroy()
        return false, 'AVATAR REQUEST SUPERSEDED'
    end
    local snapshot, captureError = Runtime.AvatarWeapons:Begin(character, localPlayer:FindFirstChild('Backpack'))
    if not snapshot then description:Destroy(); return false, captureError end
    local completed, result, reason = xpcall(function()
        local applyOk, applyErr = pcall(function() humanoid:ApplyDescriptionReset(description) end)
        if not applyOk and Runtime.AvatarWeapons:IsCurrent(snapshot) then
            applyOk, applyErr = pcall(function() humanoid:ApplyDescription(description) end)
        end
        if not Runtime.AvatarWeapons:IsCurrent(snapshot) then return false, 'CHARACTER CHANGED' end
        if not applyOk then
            warn('[Carti Hub] HumanoidDescription apply failed, using model copy fallback: ' .. tostring(applyErr))
            applyBodyDescriptionValues(humanoid, description)
            return applyAvatarByGeneratedModel(userId, character)
        end
        return true
    end, debug.traceback)
    description:Destroy()
    local rebound = Runtime.AvatarWeapons:Finish(snapshot)
    if not completed then warn('[Carti Hub] Avatar change failed: ' .. tostring(result)); return false, 'AVATAR CHANGE FAILED' end
    if not rebound then return false, 'CHARACTER CHANGED' end
    if result then avatarPersistenceState.UserId = userId end
    return result, reason
end

avatarPersistenceState.Connection = Runtime.connect(localPlayer.CharacterAdded, function(character)
    local savedUserId = avatarPersistenceState.UserId
    if not savedUserId then
        return
    end

    task.spawn(function()
        local humanoid = character:FindFirstChildOfClass("Humanoid")
            or character:WaitForChild("Humanoid", 5)
        if not humanoid then
            return
        end

        task.wait(0.35)
        if avatarPersistenceState.UserId == savedUserId and character == localPlayer.Character then
            local ok, errText = applyAvatarFromUserId(savedUserId)
            if not ok then
                warn("[Carti Hub] Could not restore saved avatar: " .. tostring(errText))
            end
        end
    end)
end)

Runtime.connect(AvatarChangerBtn.MouseButton1Click, function()
    AvatarChangerFrame.Visible = not AvatarChangerFrame.Visible
end)

Runtime.connect(AvatarChangerCloseBtn.MouseButton1Click, function()
    AvatarChangerFrame.Visible = false
end)

Runtime.connect(AvatarChangeBtn.MouseButton1Click, function()
    local ok, errText = applyAvatarFromUserId(AvatarUserIdBox.Text)
    setAvatarButtonText(AvatarChangeBtn, ok and "AVATAR CHANGED" or tostring(errText or "FAILED"))
end)

Runtime.connect(AvatarResetBtn.MouseButton1Click, function()
    local ok, errText = applyAvatarFromUserId(localPlayer.UserId)
    setAvatarButtonText(AvatarResetBtn, ok and "AVATAR RESET" or tostring(errText or "FAILED"))
end)

Runtime.connect(AvatarUserIdBox.FocusLost, function(enterPressed)
    if enterPressed and AvatarUserIdBox.Text ~= "" then
        local ok, errText = applyAvatarFromUserId(AvatarUserIdBox.Text)
        setAvatarButtonText(AvatarChangeBtn, ok and "AVATAR CHANGED" or tostring(errText or "FAILED"))
    end
end)
end

local customUsers = {
    "XKylie_2010", "lakyboxsuperfann", "staglagala", "Anniev6157", "Augus0260", "carla_zion1",
    "itsme_ai1231", "itsme_llehvher", "GamergirlYT34577", "itsme_jane714", "Elle_62673",
    "urbb_jing", "Littlecupcake092389", "sampotieee", "etzorr_block", "jhanver_12906",
    "zoey685547", "baconkind68", "Amberx_xplayzz", "ethantherealsniper", "PrimPrim88009",
    "zxrcsiq", "jejemonlottto", "L0veBound", "iixemmyy", "gwapopan_j9912", "z0mbi33sr",
    "balakajan_12345", "black_totts", "ItzYoBoiJr", "harred1235", "ezz_game1234",
    "babu_5961", "lewis3417", "atm0sfer4", "kertkertgold", "They1uv_Z", "jindc4",
    "its_acegaming16", "GManU002", "x19soul", "Bluelockgod12101", "Itz_AlexandraPH",
    "BarbaFam9166", "STEVEN_AOTlol", "yea_yes21", "xXVanilla0re0Xx", "ashtine_be76",
    "Axisp0", "mine_nuwe", "Robloxiana3o2w6j0c", "eR050r", "boba_camnti", "Killer_03boy",
    "kevingnx102", "White170256", "crepecpu", "Sigma_of404", "winnerReD15", "Bos_s123456",
    "bombardio_duck", "jayabearrpurr", "mawgindonut", "ClaraZIzose", "qazwsxedcrfvtyhbj",
    "XxTWIC3xX", "adc_12367", "your_babyvincris", "killernaid2021", "dark_moon092",
    "jumar332211", "Cambo9", "MRSCHOCOLATE321", "kfiefiaiuy8e", "Pookung_M", "Ameerzelen",
    "Poolxdwwwww", "EIEIPROGG3", "darwisy_231115", "setan_4540", "xerluv", "Xarrense",
    "fl1xkr_xx", "zhenya_13008", "kinji3488", "0kayaddi", "AmirGtMl", "kdkei290",
    "fuji_XxD", "g0uu79024qtu05gq2ryg", "Angela320224", "mimpoopyui", "ukuha_tobe",
    "Ariayourpookie", "D1N0ST3R", "Eguiller2", "JSBoss1111", "DanielLikesRice2",
    "shanksthegreat26", "aydendesu", "tantoy123x6", "james1004338", "avoidsica",
}

local currentFakeTradeSenderName = "RandomPlayer"
_G.CartiHubLastTradedPlayerName = _G.CartiHubLastTradedPlayerName
_G.CartiHubPendingFakeTradeUsername = nil
_G.CartiHubActiveFakeTradeUsername = nil
_G.CartiHubFakeTradeActive = false
_G.CartiHubDebugFakeTradeAccept = false

local function pickFakeTradeSenderName()
    currentFakeTradeSenderName = customUsers[math.random(1, #customUsers)] or "RandomPlayer"
    return currentFakeTradeSenderName
end

function CartiHubNormalizeTradeUsername(username)
    username = tostring(username or "")
    username = username:gsub("^%s*%(", ""):gsub("%)%s*$", "")
    username = username:gsub("^@", "")
    username = username:gsub("^%s+", ""):gsub("%s+$", "")

    if username == "" or username == "RandomPlayer" then
        return nil
    end

    return username
end

function CartiHubSetLastTradedPlayerName(username)
    username = CartiHubNormalizeTradeUsername(username)

    if username and username ~= localPlayer.Name then
        _G.CartiHubLastTradedPlayerName = username

        if CartiHubTryAutoSelectLastTraded then
            CartiHubTryAutoSelectLastTraded(username)
        end
    end

    return _G.CartiHubLastTradedPlayerName
end

function CartiHubGetPlayerNameFromTradeText(text)
    text = CartiHubNormalizeTradeUsername(text)
    if not text then
        return nil
    end

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= localPlayer then
            local playerName = tostring(player.Name)
            local displayName = tostring(player.DisplayName or "")

            if text == playerName
                or text == displayName
                or text:find(playerName, 1, true)
                or (displayName ~= "" and text:find(displayName, 1, true)) then
                return playerName
            end
        end
    end

    return nil
end

function CartiHubUpdateLastTradedPlayerFromGui()
    if _G.CartiHubFakeTradeActive then
        return _G.CartiHubLastTradedPlayerName
    end

    local gui = tradeModule.GUI
    local tradeGui = gui and gui.TradeGUI
    if not tradeGui or not tradeGui.Enabled then
        return _G.CartiHubLastTradedPlayerName
    end

    local theirOffer = gui.TheirOffer
    local usernameLabel = theirOffer and theirOffer:FindFirstChild("Username")
    local playerName = usernameLabel and CartiHubGetPlayerNameFromTradeText(usernameLabel.Text)

    if playerName and playerName ~= currentFakeTradeSenderName then
        return CartiHubSetLastTradedPlayerName(playerName)
    end

    return _G.CartiHubLastTradedPlayerName
end

function CartiHubGetLastTradedPlayerName()
    local detectedName = CartiHubUpdateLastTradedPlayerFromGui()
    if detectedName then
        return detectedName
    end

    if _G.CartiHubLastTradedPlayerName then
        return _G.CartiHubLastTradedPlayerName
    end

    local gui = tradeModule.GUI
    local theirOffer = gui and gui.TheirOffer
    local usernameLabel = theirOffer and theirOffer:FindFirstChild("Username")

    return usernameLabel and CartiHubSetLastTradedPlayerName(usernameLabel.Text) or nil
end

task.spawn(function()
    while SakaUI == nil or SakaUI.Parent ~= nil do
        local gui = tradeModule.GUI
        local tradeGui = gui and gui.TradeGUI
        local theirOffer = gui and gui.TheirOffer
        local usernameLabel = theirOffer and theirOffer:FindFirstChild("Username")

        if not _G.CartiHubFakeTradeActive and tradeGui and tradeGui.Enabled and usernameLabel then
            local username = CartiHubGetPlayerNameFromTradeText(usernameLabel.Text)

            if username and username ~= currentFakeTradeSenderName then
                CartiHubSetLastTradedPlayerName(username)
            end
        end

        if not _G.CartiHubFakeTradeActive and tradeGui and tradeGui.Enabled then
            CartiHubUpdateLastTradedPlayerFromGui()
        end

        task.wait(0.5)
    end
end)

local function getFakeTradeSenderName()
    return currentFakeTradeSenderName or "RandomPlayer"
end

function CartiHubApplyPendingFakeTradeUsername()
    local pendingName = _G.CartiHubPendingFakeTradeUsername or _G.CartiHubActiveFakeTradeUsername
    local gui = tradeModule.GUI
    local theirOffer = gui and gui.TheirOffer
    local usernameLabel = theirOffer and theirOffer:FindFirstChild("Username")

    if not pendingName or not usernameLabel then
        return
    end

    usernameLabel.Text = "(" .. tostring(pendingName) .. ")"
end

local function getFriendJoinThumbnail(username)
    local ok, userId = pcall(function()
        return Players:GetUserIdFromNameAsync(username)
    end)

    if not ok or not userId then
        return "rbxthumb://type=AvatarHeadShot&id=1&w=150&h=150"
    end

    return ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(userId)
end

local function showFriendJoinSystemMessage(username)
    local message = ("Your friend %s has joined the game."):format(username)
    local textChatOk = pcall(function()
        local TextChatService = game:GetService("TextChatService")
        local channels = TextChatService:FindFirstChild("TextChannels")
        local systemChannel = channels and (
            channels:FindFirstChild("RBXSystem")
            or channels:FindFirstChild("RBXGeneral")
        )

        if systemChannel then
            systemChannel:DisplaySystemMessage(
                '<font color="rgb(255,255,255)">' .. message .. '</font>'
            )
        else
            error("No TextChatService system channel")
        end
    end)

    if textChatOk then
        return true
    end

    local StarterGui = game:GetService("StarterGui")
    for _ = 1, 20 do
        local legacyOk = pcall(function()
            StarterGui:SetCore("ChatMakeSystemMessage", {
                Text = message,
                Color = Color3.fromRGB(255, 255, 255),
                Font = Enum.Font.SourceSans,
                TextSize = 18,
            })
        end)

        if legacyOk then
            return true
        end

        task.wait(0.25)
    end

    warn("[Carti Hub] Could not show friend join chat notification.")
    return false
end

local friendJoinToastSequence = 0

local function showFriendJoinTopToast(username)
    friendJoinToastSequence += 1
    local sequence = friendJoinToastSequence
    local parent = safeParent()

    local oldGui = parent:FindFirstChild("CartiHubFriendJoinTopToast")
    if oldGui then
        oldGui:Destroy()
    end

    local gui = Runtime.screenGui()
    gui.Name = "CartiHubFriendJoinTopToast"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = false
    gui.DisplayOrder = 100000
    gui.Parent = parent

    local toastText = tostring(username) .. " joined you"

    local holder = Instance.new("Frame")
    holder.AnchorPoint = Vector2.new(0.5, 0)
    holder.Size = UDim2.new(0, 405, 0, 58)
    holder.Position = UDim2.new(0.5, 0, 0, -72)
    holder.BackgroundTransparency = 1
    holder.Parent = gui

    local scale = Instance.new("UIScale")
    scale.Scale = 1
    scale.Parent = holder

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromScale(1, 1)
    frame.BackgroundColor3 = Color3.fromRGB(90, 91, 97)
    frame.BackgroundTransparency = 0
    frame.BorderSizePixel = 0
    frame.Parent = holder
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)

    local gradient = Instance.new("UIGradient")
    gradient.Rotation = 90
    gradient.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(118, 119, 126)),
        ColorSequenceKeypoint.new(0.45, Color3.fromRGB(98, 99, 106)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 81, 88)),
    })
    gradient.Parent = frame

    local avatar = Instance.new("ImageLabel")
    avatar.Size = UDim2.new(0, 36, 0, 36)
    avatar.Position = UDim2.new(0, 12, 0.5, -18)
    avatar.BackgroundColor3 = Color3.fromRGB(18, 18, 20)
    avatar.BorderSizePixel = 0
    avatar.Image = getFriendJoinThumbnail(username)
    avatar.Parent = frame
    Instance.new("UICorner", avatar).CornerRadius = UDim.new(1, 0)

    local avatarStroke = Instance.new("UIStroke")
    avatarStroke.Color = Color3.fromRGB(0, 105, 210)
    avatarStroke.Transparency = 0
    avatarStroke.Thickness = 1
    avatarStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    avatarStroke.Parent = avatar

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -66, 1, 0)
    title.Position = UDim2.new(0, 58, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = toastText
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.Font = Enum.Font.BuilderSansBold
    title.TextSize = 18
    title.TextTruncate = Enum.TextTruncate.AtEnd
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextYAlignment = Enum.TextYAlignment.Center
    title.Parent = frame

    if holder.AbsoluteSize.X > 0 and holder.AbsoluteSize.X > gui.AbsoluteSize.X - 24 then
        scale.Scale = math.max(0.72, (gui.AbsoluteSize.X - 24) / holder.AbsoluteSize.X)
    end

    TweenService:Create(holder, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
        Position = UDim2.new(0.5, 0, 0, -30),
    }):Play()

    task.delay(4.5, function()
        if sequence ~= friendJoinToastSequence or not holder.Parent then
            return
        end

        TweenService:Create(holder, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
            Position = UDim2.new(0.5, 0, 0, -72),
        }):Play()

        TweenService:Create(frame, TweenInfo.new(0.2), {
            BackgroundTransparency = 1,
        }):Play()

        task.wait(0.28)
        if gui.Parent then
            gui:Destroy()
        end
    end)
end

local function showFakeFriendJoinNotification(username)
    username = username or customUsers[math.random(1, #customUsers)] or "RobloxPlayer"
    showFriendJoinSystemMessage(username)
    showFriendJoinTopToast(username)
end

local function showRandomFakeFriendJoinNotification()
    showFakeFriendJoinNotification(customUsers[math.random(1, #customUsers)])
end

local function setAutoFriendJoinEnabled(enabled)
    autoFriendJoinEnabled = enabled
    autoFriendJoinSequence += 1
    local sequence = autoFriendJoinSequence

    AutoFriendJoinBtn.Text = enabled and "AUTO FRIEND JOIN: ON" or "AUTO FRIEND JOIN: OFF"
    AutoFriendJoinBtn.BackgroundColor3 = enabled and BUTTON_HOVER_COLOR or BUTTON_COLOR

    if not enabled then
        return
    end

    task.spawn(function()
        while autoFriendJoinEnabled and sequence == autoFriendJoinSequence and SakaUI and SakaUI.Parent do
            showRandomFakeFriendJoinNotification()

            local waitRemaining = math.max(1, tonumber(friendJoinDelaySeconds) or 30)
            while waitRemaining > 0 and autoFriendJoinEnabled and sequence == autoFriendJoinSequence do
                task.wait(math.min(1, waitRemaining))
                waitRemaining -= 1
            end
        end
    end)
end

Runtime.connect(FriendJoinToggleBtn.MouseButton1Click, function()
    showRandomFakeFriendJoinNotification()
end)

Runtime.connect(AutoFriendJoinBtn.MouseButton1Click, function()
    setAutoFriendJoinEnabled(not autoFriendJoinEnabled)
end)

local theirOffer = {}
local localOffer = {}
local localAcceptMode = "Accept"
local localConfirmStartedAt = 0
local cooldownEndsAt = 0
local cooldownSequence = 0
local otherAcceptSequence = 0
local redrawLocalTrade
local resetAcceptUi
local installOfferRemoveButtons
local refreshMainInventoryQueued = false

local function cleanupOldOverlays()
    local gui = tradeModule.GUI
    if not gui then
        return
    end

    for _, root in ipairs({ gui.TradeGUI }) do
        if root then
            for _, descendant in ipairs(root:GetDescendants()) do
                if descendant.Name == "ClientPlaceholderTradeRemove"
                    or descendant.Name == "ClientPlaceholderTradeToggle"
                    or descendant.Name == "ClientPlaceholderTradeAcceptBridge"
                    or descendant.Name == "ClientPlaceholderTradeAcceptOverlay"
                    or descendant.Name == "ClientPlaceholderTradeActionOverlay"
                    or descendant.Name == "CartiHubFakeTradeWatermark" then
                    descendant:Destroy()
                end
            end
        end
    end
end

-- All fake-trade controls are parented into the game's shared trade GUI. They
-- must be removed before the next real trade or they intercept its buttons.
function CartiHubEndFakeTradeSession()
    _G.CartiHubFakeTradeActive = false
    _G.CartiHubFakeTradeVisualSequence = (_G.CartiHubFakeTradeVisualSequence or 0) + 1
    _G.CartiHubAutoTradeOfferSequence = (_G.CartiHubAutoTradeOfferSequence or 0) + 1
    _G.CartiHubPendingFakeTradeUsername = nil
    _G.CartiHubActiveFakeTradeUsername = nil
    _G.CartiHubInstantFakeTradeReturnPending = false

    if CartiHubDisconnectFakeTradeFrameGuardSignals then
        CartiHubDisconnectFakeTradeFrameGuardSignals()
    end

    cleanupOldOverlays()
end

local function clearLeakedFakeTradeControls()
    if _G.CartiHubFakeTradeActive then
        return
    end

    local gui = tradeModule.GUI
    local tradeGui = gui and gui.TradeGUI
    if not tradeGui then
        return
    end

    local leaked = false
    for _, descendant in ipairs(tradeGui:GetDescendants()) do
        if descendant.Name == "ClientPlaceholderTradeActionOverlay"
            or descendant.Name == "ClientPlaceholderTradeToggle"
            or descendant.Name == "ClientPlaceholderTradeRemove"
            or descendant.Name == "CartiHubFakeTradeWatermark" then
            leaked = true
            break
        end
    end

    if leaked then
        CartiHubEndFakeTradeSession()
    end
end

task.spawn(function()
    while SakaUI == nil or SakaUI.Parent ~= nil do
        clearLeakedFakeTradeControls()
        task.wait(0.2)
    end
end)

local function clearOfferSlots(offerFrame)
    if not offerFrame or not offerFrame:FindFirstChild("Container") then
        return
    end

    for index = 1, 4 do
        local slot = offerFrame.Container:FindFirstChild("NewItem" .. index)
        if slot then
            itemModule.DisplayItem(slot, nil)
            slot.Visible = false
        end
    end
end

local function copyItemData(itemId, itemType, amount)
    local source = sync[itemType] and sync[itemType][itemId]
    if not source then
        return nil
    end

    local data = {}
    for key, value in pairs(source) do
        data[key] = value
    end

    data.DataType = itemType
    data.Amount = amount or 1
    return data
end

local function refreshMainInventoryItem()
    if refreshMainInventoryQueued then
        return
    end

    refreshMainInventoryQueued = true

    task.defer(function()
        refreshMainInventoryQueued = false
        refreshMainInventoryNow()
    end)
end

local function isTradeGuiOpen()
    return tradeModule.GUI
        and tradeModule.GUI.TradeGUI
        and tradeModule.GUI.TradeGUI.Enabled
end

local function applyInventoryDelta(itemId, itemType, delta)
    local owned = getProfileOwnedTable(itemType)
    if not owned then
        warn(("[IncomingTradePopup] No local owned table for %s/%s"):format(tostring(itemType), tostring(itemId)))
        return
    end

    local current = Runtime.Inventory.visibleAmount(itemId, itemType)
    delta = math.max(-current, Runtime.Inventory.amount(delta))
    local key = CartiHubGetFakeInventoryKey(itemId, itemType)
    Runtime.Inventory.Deltas[key] = (Runtime.Inventory.Deltas[key] or 0) + delta
    if Runtime.Inventory.Deltas[key] == 0 then Runtime.Inventory.Deltas[key] = nil end

    local tradeInventory = tradeModule.TradeInventory
    local entry = tradeInventory
        and tradeInventory.Data
        and tradeInventory.Data[itemType]
        and tradeInventory.Data[itemType].Current
        and tradeInventory.Data[itemType].Current[itemId]

    if entry then
        entry.Amount = math.max(0, (tonumber(entry.Amount) or current) + delta)

        if entry.Frame then
            if entry.Amount <= 0 then
                entry.Frame.Visible = false
            else
                local itemData = copyItemData(itemId, itemType, entry.Amount)
                if itemData then
                    itemModule.DisplayItem(entry.Frame, itemData, nil, true)
                end
                entry.Frame.Visible = true
            end
        end
    end

    if not isTradeGuiOpen() then
        task.defer(refreshMainInventoryItem)
    end
end

local function restoreLocalOfferToInventory()
    for _, offer in ipairs(localOffer) do
        applyInventoryDelta(offer.ItemID, offer.ItemType, offer.Amount or 1)
    end

    table.clear(localOffer)
end

local function addTheirOfferToInventory(offerList)
    for _, offer in ipairs(offerList or theirOffer) do
        applyInventoryDelta(offer.ItemID, offer.ItemType, offer.Amount or 1)
    end
end

_G.CartiHubSeasonalOfferTagConnections = _G.CartiHubSeasonalOfferTagConnections or {}

function CartiHubClearSeasonalOfferTagGuards(slot)
    local tags = slot and slot:FindFirstChild("Tags", true)
    if not tags then
        return
    end

    for _, tagName in ipairs({ "Halloween", "Christmas" }) do
        local tag = tags:FindFirstChild(tagName)
        local connection = tag and _G.CartiHubSeasonalOfferTagConnections[tag]
        if connection then
            connection:Disconnect()
            _G.CartiHubSeasonalOfferTagConnections[tag] = nil
        end
    end
end

function CartiHubHideSeasonalOfferTags(slot)
    local tags = slot and slot:FindFirstChild("Tags", true)
    if not tags then
        return
    end

    for _, tagName in ipairs({ "Halloween", "Christmas" }) do
        local tag = tags:FindFirstChild(tagName)
        if tag and tag:IsA("GuiObject") then
            local oldConnection = _G.CartiHubSeasonalOfferTagConnections[tag]
            if oldConnection then
                oldConnection:Disconnect()
            end

            tag.Visible = false
            _G.CartiHubSeasonalOfferTagConnections[tag] = Runtime.connect(tag:GetPropertyChangedSignal("Visible"), function()
                if tag.Parent and tag.Visible then
                    tag.Visible = false
                end
            end)
        end
    end
end

local function drawOfferSlots(offerFrame, offerList)
    clearOfferSlots(offerFrame)

    for index, offer in ipairs(offerList) do
        local slot = offerFrame
            and offerFrame:FindFirstChild("Container")
            and offerFrame.Container:FindFirstChild("NewItem" .. index)

        local itemData = copyItemData(offer.ItemID, offer.ItemType, offer.Amount)
        if slot and itemData then
            CartiHubClearSeasonalOfferTagGuards(slot)
            itemModule.DisplayItem(slot, itemData)
            if offer.HideSeasonalTags then
                CartiHubHideSeasonalOfferTags(slot)
            end
            slot.Visible = true
        end
    end
end

function CartiHubEnforceFakeTradeFrame()
    if not _G.CartiHubFakeTradeActive or not tradeModule.GUI or not tradeModule.GUI.TradeGUI then
        return
    end

    if not Runtime.tradeOpen() then
        tradeModule.GUI.TradeGUI.Enabled = true
    end

    if tradeModule.GUI.TradeGUI:FindFirstChild("Container") then
        tradeModule.GUI.TradeGUI.Container.Visible = true
    end

    if localAcceptMode == "Waiting" or localAcceptMode == "BothAccepted" then
        return
    end

    drawOfferSlots(tradeModule.GUI.YourOffer, localOffer)
    drawOfferSlots(tradeModule.GUI.TheirOffer, theirOffer)

    if tradeModule.GUI.TheirOffer and tradeModule.GUI.TheirOffer:FindFirstChild("Username") then
        tradeModule.GUI.TheirOffer.Username.Text = "(" .. getFakeTradeSenderName() .. ")"
        CartiHubApplyPendingFakeTradeUsername()
    end

    if installOfferRemoveButtons then
        installOfferRemoveButtons()
    end

    if localAcceptMode == "Accept" then
        CartiHubWakeAcceptActionButton()
    else
        CartiHubSetAcceptContainerOverlayVisible(false)
    end

    CartiHubTraceFakeAcceptState("enforce")
end

function CartiHubQueueFakeTradeFrameRepair()
    if not _G.CartiHubFakeTradeActive then
        return
    end

    task.defer(CartiHubEnforceFakeTradeFrame)
end

function CartiHubDisconnectFakeTradeFrameGuardSignals()
    _G.CartiHubAutoTradeOfferSequence = (_G.CartiHubAutoTradeOfferSequence or 0) + 1

    for _, connection in ipairs(_G.CartiHubFakeTradeGuardConnections or {}) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    _G.CartiHubFakeTradeGuardConnections = {}

    if _G.CartiHubFakeTradeSearchConnection then
        pcall(function()
            _G.CartiHubFakeTradeSearchConnection:Disconnect()
        end)
        _G.CartiHubFakeTradeSearchConnection = nil
    end
end

function CartiHubConnectFakeTradeFrameGuardSignals()
    CartiHubDisconnectFakeTradeFrameGuardSignals()

    local gui = tradeModule.GUI
    local tradeGui = gui and gui.TradeGUI
    _G.CartiHubFakeTradeGuardConnections = {}

    if tradeGui then
        table.insert(_G.CartiHubFakeTradeGuardConnections, Runtime.connect(tradeGui:GetPropertyChangedSignal("Enabled"), CartiHubQueueFakeTradeFrameRepair))

        if tradeGui:FindFirstChild("Container") then
            table.insert(_G.CartiHubFakeTradeGuardConnections, Runtime.connect(tradeGui.Container:GetPropertyChangedSignal("Visible"), CartiHubQueueFakeTradeFrameRepair))
        end
    end

end

function CartiHubStartFakeTradeFrameGuard()
    _G.CartiHubFakeTradeVisualSequence = (_G.CartiHubFakeTradeVisualSequence or 0) + 1
    local sequence = _G.CartiHubFakeTradeVisualSequence
    CartiHubConnectFakeTradeFrameGuardSignals()

    task.spawn(function()
        while _G.CartiHubFakeTradeActive
            and sequence == _G.CartiHubFakeTradeVisualSequence
            and SakaUI
            and SakaUI.Parent do
            CartiHubEnforceFakeTradeFrame()
            task.wait(0.08)
        end

        if sequence == _G.CartiHubFakeTradeVisualSequence then
            CartiHubDisconnectFakeTradeFrameGuardSignals()
        end
    end)
end

local function setLocalAcceptState(mode)
    local actions = tradeModule.GUI.Actions
    local accept = actions and actions:FindFirstChild("Accept")
    if not accept then
        return
    end

    localAcceptMode = mode

    if accept:FindFirstChild("Confirm") then
        accept.Confirm.Visible = mode == "Confirm"
    end

    if accept:FindFirstChild("Cancel") then
        accept.Cancel.Visible = mode == "Waiting" or mode == "BothAccepted"
    end

    if accept:FindFirstChild("Cooldown") and mode ~= "Cooldown" then
        accept.Cooldown.Visible = false
    end

    if accept:FindFirstChild("AddItem") then
        accept.AddItem.Visible = mode == "Cooldown"
    end

    if tradeModule.GUI.YourOffer:FindFirstChild("Accepted") then
        tradeModule.GUI.YourOffer.Accepted.Visible = mode == "Waiting" or mode == "BothAccepted"
    end

    if tradeModule.GUI.TheirOffer:FindFirstChild("Accepted") then
        tradeModule.GUI.TheirOffer.Accepted.Visible = mode == "BothAccepted"
    end

    CartiHubSetAcceptContainerOverlayVisible(mode == "Accept")
end

function CartiHubHandleFakeAcceptClick()
    if not Runtime.tradeOpen() then return end
    CartiHubTraceFakeAcceptState("accept_click")

    if localAcceptMode == "Accept" and time() >= cooldownEndsAt then
        localConfirmStartedAt = time()
        setLocalAcceptState("Confirm")
        CartiHubTraceFakeAcceptState("accept_to_confirm")
    end
end

function CartiHubSetAcceptContainerOverlayVisible(visible)
    local actions = tradeModule.GUI and tradeModule.GUI.Actions
    local accept = actions and actions:FindFirstChild("Accept")
    local overlay = accept and accept:FindFirstChild("ClientPlaceholderTradeActionOverlay")

    if overlay and overlay:IsA("GuiObject") then
        overlay.Visible = visible
    end
end

function CartiHubTraceFakeAcceptState(reason)
    return
end

function CartiHubWakeAcceptActionButton()
    -- Closing resets the accept state and can leave deferred wake callbacks.
    -- They must not recreate overlays on the game's shared UI after cleanup.
    if not Runtime.Active or not _G.CartiHubFakeTradeActive then return end
    local actions = tradeModule.GUI and tradeModule.GUI.Actions
    local accept = actions and actions:FindFirstChild("Accept")
    if not accept then
        return
    end

    accept.Visible = true

    if accept:FindFirstChild("Cooldown") and localAcceptMode ~= "Cooldown" then
        accept.Cooldown.Visible = false
    end

    if accept:FindFirstChild("AddItem") and localAcceptMode ~= "Cooldown" then
        accept.AddItem.Visible = false
    end

    if accept:FindFirstChild("Confirm") and localAcceptMode ~= "Confirm" then
        accept.Confirm.Visible = false
    end

    if accept:FindFirstChild("Cancel") and localAcceptMode ~= "Waiting" and localAcceptMode ~= "BothAccepted" then
        accept.Cancel.Visible = false
    end

    local actionButton = accept:FindFirstChild("ActionButton")
    if actionButton and actionButton:IsA("GuiObject") then
        actionButton.Visible = true
        actionButton.ZIndex = math.max(actionButton.ZIndex, accept.ZIndex + 1)
    end

    if actionButton and actionButton:IsA("GuiButton") then
        actionButton.Active = true
        actionButton.Selectable = true
        actionButton.AutoButtonColor = true
    end

    local containerOverlay = accept:FindFirstChild("ClientPlaceholderTradeActionOverlay")
    if not containerOverlay then
        containerOverlay = Instance.new("TextButton")
        containerOverlay.Name = "ClientPlaceholderTradeActionOverlay"
        containerOverlay.BackgroundTransparency = 1
        containerOverlay.BorderSizePixel = 0
        containerOverlay.Text = ""
        containerOverlay.Size = UDim2.fromScale(1, 1)
        containerOverlay.Position = UDim2.fromScale(0, 0)
        containerOverlay.Parent = accept
        Runtime.connect(containerOverlay.MouseButton1Click, CartiHubHandleFakeAcceptClick)
    end

    if containerOverlay:IsA("GuiObject") then
        containerOverlay.Visible = localAcceptMode == "Accept"
        containerOverlay.BackgroundTransparency = 1
        containerOverlay.ZIndex = accept.ZIndex + 200
        containerOverlay.Size = UDim2.fromScale(1, 1)
        containerOverlay.Position = UDim2.fromScale(0, 0)
    end

    if containerOverlay:IsA("GuiButton") then
        containerOverlay.Active = true
        containerOverlay.Selectable = true
        containerOverlay.AutoButtonColor = false
    end

    local overlay = actionButton and actionButton:FindFirstChild("ClientPlaceholderTradeActionOverlay")
    if actionButton and not overlay then
        overlay = Instance.new("TextButton")
        overlay.Name = "ClientPlaceholderTradeActionOverlay"
        overlay.BackgroundTransparency = 1
        overlay.BorderSizePixel = 0
        overlay.Text = ""
        overlay.Size = UDim2.fromScale(1, 1)
        overlay.Position = UDim2.fromScale(0, 0)
        overlay.Parent = actionButton
        Runtime.connect(overlay.MouseButton1Click, CartiHubHandleFakeAcceptClick)
    end

    if overlay and overlay:IsA("GuiObject") then
        overlay.Visible = localAcceptMode == "Accept"
        overlay.BackgroundTransparency = 1
        overlay.ZIndex = actionButton.ZIndex + 100
        overlay.Size = UDim2.fromScale(1, 1)
        overlay.Position = UDim2.fromScale(0, 0)
    end

    if overlay and overlay:IsA("GuiButton") then
        overlay.Active = true
        overlay.Selectable = true
        overlay.AutoButtonColor = false
    end

    CartiHubTraceFakeAcceptState("wake")
end

function CartiHubForceFakeAcceptReady()
    if not _G.CartiHubFakeTradeActive then
        return
    end

    localAcceptMode = "Accept"

    local actions = tradeModule.GUI and tradeModule.GUI.Actions
    local accept = actions and actions:FindFirstChild("Accept")

    if accept then
        accept.Visible = true

        if accept:FindFirstChild("Cooldown") then
            accept.Cooldown.Visible = false
        end

        if accept:FindFirstChild("AddItem") then
            accept.AddItem.Visible = false
        end

        if accept:FindFirstChild("Confirm") then
            accept.Confirm.Visible = false
        end

        if accept:FindFirstChild("Cancel") then
            accept.Cancel.Visible = false
        end
    end

    CartiHubWakeAcceptActionButton()
    CartiHubSetAcceptContainerOverlayVisible(true)
    CartiHubTraceFakeAcceptState("force_ready")
end

function CartiHubStabilizeFakeAcceptReady(sequence)
    task.spawn(function()
        for _ = 1, 8 do
            if sequence ~= cooldownSequence or not _G.CartiHubFakeTradeActive or localAcceptMode ~= "Accept" then
                return
            end

            CartiHubForceFakeAcceptReady()
            task.wait(0.05)
        end
    end)
end

local function promptReceivedTheirOfferItems(offerList)
    for _, offer in ipairs(offerList or theirOffer) do
        local ok, err = pcall(function()
            itemPopupService:AddNewItem(offer.ItemID, offer.ItemType, offer.Amount or 1)
        end)

        if not ok then
            warn(("[IncomingTradePopup] Item popup failed for %s/%s: %s"):format(
                tostring(offer.ItemType),
                tostring(offer.ItemID),
                tostring(err)
            ))
        end
    end
end

local function scheduleOtherSideAccept()
    otherAcceptSequence += 1
    local sequence = otherAcceptSequence
    local delaySeconds = math.random(10, 30) / 10

    task.delay(delaySeconds, function()
        if sequence ~= otherAcceptSequence or localAcceptMode ~= "Waiting" then
            return
        end

        if tradeModule.GUI.TheirOffer:FindFirstChild("Accepted") then
            tradeModule.GUI.TheirOffer.Accepted.Visible = true
        end

        task.delay(1, function()
            if sequence ~= otherAcceptSequence or localAcceptMode ~= "Waiting" then
                return
            end

            local tradeGui = tradeModule.GUI.TradeGUI
            local receivedItems = {}
            local returnTradeUsername = _G.CartiHubInstantFakeTradeReturnPending
                and getFakeTradeSenderName()

            _G.CartiHubInstantFakeTradeReturnPending = false

            for _, offer in ipairs(theirOffer) do
                table.insert(receivedItems, {
                    ItemID = offer.ItemID,
                    ItemType = offer.ItemType,
                    Amount = offer.Amount or 1,
                })
            end

            tradeGui.Enabled = false
            CartiHubEndFakeTradeSession()
            addTheirOfferToInventory(receivedItems)
            refreshMainInventoryItem()
            promptReceivedTheirOfferItems(receivedItems)
            tradeModule.TradeInventory = nil
            table.clear(localOffer)
            table.clear(theirOffer)
            resetAcceptUi()
            clearOfferSlots(tradeModule.GUI.YourOffer)
            clearOfferSlots(tradeModule.GUI.TheirOffer)

            if returnTradeUsername then
                task.delay(math.random(20, 40) / 10, function()
                    if SakaUI and SakaUI.Parent and CartiHubLaunchInstantFakePersonTrade then
                        CartiHubLaunchInstantFakePersonTrade(returnTradeUsername, true)
                    end
                end)
            end
        end)
    end)
end

local function startAcceptCooldown(seconds)
    local actions = tradeModule.GUI.Actions
    local accept = actions and actions:FindFirstChild("Accept")
    local cooldown = accept and accept:FindFirstChild("Cooldown")
    local title = cooldown and cooldown:FindFirstChild("Title")

    if not cooldown then
        return
    end

    cooldownSequence += 1
    local sequence = cooldownSequence
    cooldownEndsAt = time() + seconds
    localAcceptMode = "Cooldown"

    if accept:FindFirstChild("Confirm") then
        accept.Confirm.Visible = false
    end

    if accept:FindFirstChild("Cancel") then
        accept.Cancel.Visible = false
    end

    if tradeModule.GUI.YourOffer:FindFirstChild("Accepted") then
        tradeModule.GUI.YourOffer.Accepted.Visible = false
    end

    cooldown.Visible = true
    CartiHubSetAcceptContainerOverlayVisible(false)
    CartiHubTraceFakeAcceptState("cooldown_start")

    task.spawn(function()
        while sequence == cooldownSequence do
            local remaining = math.max(0, math.ceil(cooldownEndsAt - time()))
            if title then
                title.Text = ("Please wait (%d) before accepting."):format(remaining)
            end

            if remaining <= 0 then
                break
            end

            task.wait(0.2)
        end

        if sequence == cooldownSequence then
            CartiHubTraceFakeAcceptState("cooldown_end_before_ready")
            CartiHubForceFakeAcceptReady()
            CartiHubStabilizeFakeAcceptReady(sequence)
        end
    end)
end

resetAcceptUi = function()
    cooldownSequence += 1
    otherAcceptSequence += 1
    cooldownEndsAt = 0
    setLocalAcceptState("Accept")
    CartiHubWakeAcceptActionButton()
    task.defer(CartiHubWakeAcceptActionButton)

    local actions = tradeModule.GUI.Actions
    if actions and actions:FindFirstChild("oldconfirm") then
        actions.oldconfirm.Visible = false
    end
end

installOfferRemoveButtons = function()
    local yourOffer = tradeModule.GUI.YourOffer
    if not yourOffer or not yourOffer:FindFirstChild("Container") then
        return
    end

    for index = 1, 4 do
        local slot = yourOffer.Container:FindFirstChild("NewItem" .. index)
        if slot then
            local oldOverlay = slot:FindFirstChild("ClientPlaceholderTradeRemove")
            if oldOverlay then
                oldOverlay:Destroy()
            end

            if localOffer[index] then
                local overlay = Instance.new("TextButton")
                overlay.Name = "ClientPlaceholderTradeRemove"
                overlay.BackgroundTransparency = 1
                overlay.BorderSizePixel = 0
                overlay.Text = ""
                overlay.Size = UDim2.fromScale(1, 1)
                overlay.Position = UDim2.fromScale(0, 0)
                overlay.ZIndex = slot.ZIndex + 50
                overlay.Parent = slot

                Runtime.connect(overlay.MouseButton1Click, function()
                    local removed = table.remove(localOffer, index)
                    if removed then
                        applyInventoryDelta(removed.ItemID, removed.ItemType, removed.Amount or 1)
                    end

                    if redrawLocalTrade then
                        redrawLocalTrade()
                    end
                end)
            end
        end
    end
end

redrawLocalTrade = function()
    drawOfferSlots(tradeModule.GUI.YourOffer, localOffer)
    drawOfferSlots(tradeModule.GUI.TheirOffer, theirOffer)
    resetAcceptUi()
    tradeModule.GUI.TheirOffer.Username.Text = "(" .. getFakeTradeSenderName() .. ")"
    CartiHubApplyPendingFakeTradeUsername()
    installOfferRemoveButtons()
end

local function toggleLocalOffer(itemId, itemType)
    if not Runtime.tradeOpen() or Runtime.Inventory.visibleAmount(itemId, itemType) < 1 then
        return false
    end
    if not canFakeTradeItem(itemId, itemType) then
        warn(("[IncomingTradePopup] %s/%s is not tradeable."):format(tostring(itemType), tostring(itemId)))
        return
    end

    for _, offer in ipairs(localOffer) do
        if offer.ItemID == itemId and offer.ItemType == itemType then
            offer.Amount = (tonumber(offer.Amount) or 1) + 1
            applyInventoryDelta(itemId, itemType, -1)
            redrawLocalTrade()
            startAcceptCooldown(6)
            return
        end
    end

    if #localOffer >= 4 then
        warn("[IncomingTradePopup] Trade offer is full.")
        return
    end

    table.insert(localOffer, {
        ItemID = itemId,
        Amount = 1,
        ItemType = itemType,
    })

    applyInventoryDelta(itemId, itemType, -1)
    redrawLocalTrade()
    startAcceptCooldown(6)
end

function CartiHubGetFakeTradeSearchBox()
    local gui = tradeModule.GUI
    local tradeGui = gui and gui.TradeGUI

    return tradeGui
        and tradeGui:FindFirstChild("Container")
        and tradeGui.Container:FindFirstChild("Items")
        and tradeGui.Container.Items:FindFirstChild("Tabs")
        and tradeGui.Container.Items.Tabs:FindFirstChild("Search")
        and tradeGui.Container.Items.Tabs.Search:FindFirstChild("Container")
        and tradeGui.Container.Items.Tabs.Search.Container:FindFirstChild("SearchText")
end

function CartiHubStartAutoTradeOfferFill()
    _G.CartiHubAutoTradeOfferSequence = (_G.CartiHubAutoTradeOfferSequence or 0) + 1
    local sequence = _G.CartiHubAutoTradeOfferSequence

    task.spawn(function()
        local function isActive()
            return _G.CartiHubAutoTradeOfferSequence == sequence and _G.CartiHubFakeTradeActive == true
        end

        local function isAlreadyOffered(itemId, itemType)
            for _, offer in ipairs(localOffer) do
                if offer.ItemID == itemId and offer.ItemType == itemType then
                    return true
                end
            end

            return false
        end

        local function getCandidate()
            local inventory = tradeModule.TradeInventory
            local candidates = {}
            local searchTerms = _G.CartiHubAutoTradeSearchTerms

            if type(searchTerms) ~= "table" or #searchTerms == 0 then
                return nil
            end

            for itemType, typeData in pairs(inventory and inventory.Data or {}) do
                if itemType == "Weapons" or itemType == "Item" then
                    for itemId, entry in pairs(typeData.Current or {}) do
                        local availableAmount = math.max(0, math.floor(tonumber(entry.Amount) or 0))
                        if availableAmount > 0
                            and canFakeTradeItem(itemId, itemType)
                            and not isAlreadyOffered(itemId, itemType) then
                            local itemName = tostring(entry.Name or itemId)
                            local lowerItemName = itemName:lower()

                            for _, term in ipairs(searchTerms) do
                                term = tostring(term or "")
                                if term ~= "" and lowerItemName:find(term:lower(), 1, true) then
                                    table.insert(candidates, {
                                        ItemID = itemId,
                                        ItemType = itemType,
                                        Name = itemName,
                                        SearchTerm = term,
                                        AvailableAmount = availableAmount,
                                    })
                                end
                            end
                        end
                    end
                end
            end

            if #candidates == 0 then
                return nil
            end

            return candidates[math.random(1, #candidates)]
        end

        local function typeSearch(searchText, term)
            task.wait(math.random(100, 180) / 100)
            if not isActive() or not searchText.Parent then
                return false
            end

            searchText.Text = ""

            for index = 1, #term do
                if not isActive() or not searchText.Parent then
                    return false
                end

                searchText.Text = term:sub(1, index)
                task.wait(math.random(6, 16) / 100)
            end

            return true
        end

        while isActive() and #localOffer < 4 do
            local candidate = getCandidate()
            local searchText = CartiHubGetFakeTradeSearchBox()
            if not candidate or not searchText or not searchText:IsA("TextBox") then
                return
            end

            if not typeSearch(searchText, tostring(candidate.SearchTerm)) then
                return
            end

            local addCount = math.random(1, math.min(3, candidate.AvailableAmount))
            for _ = 1, addCount do
                if not isActive() then
                    return
                end

                toggleLocalOffer(candidate.ItemID, candidate.ItemType)
                task.wait(math.random(45, 90) / 100)
            end

            task.wait(math.random(20, 45) / 100)
            for index = #searchText.Text - 1, 0, -1 do
                if not isActive() or not searchText.Parent then
                    return
                end

                searchText.Text = searchText.Text:sub(1, index)
                task.wait(math.random(10, 20) / 100)
            end

            task.wait(math.random(25, 55) / 100)
        end

        while isActive() and localAcceptMode == "Cooldown" do
            task.wait(0.1)
        end

        if isActive() and #localOffer >= 4 and localAcceptMode == "Accept" then
            task.wait(math.random(35, 75) / 100)
        end

        if isActive() and #localOffer >= 4 and localAcceptMode == "Accept" then
            localConfirmStartedAt = time()
            setLocalAcceptState("Confirm")
            task.wait(math.random(60, 115) / 100)

            if isActive() and localAcceptMode == "Confirm" then
                setLocalAcceptState("Waiting")
                scheduleOtherSideAccept()
            end
        end
    end)
end

local function getRandomGodlyWeapon()
    local candidates = {}

    for itemId, data in pairs(sync.Weapons or {}) do
        if type(data) == "table"
            and data.Rarity == "Godly"
            and (data.ItemType == "Knife" or data.ItemType == "Gun")
            and canFakeTradeItem(itemId, "Weapons") then
            table.insert(candidates, {
                ItemID = itemId,
                Amount = 1,
                ItemType = "Weapons",
            })
        end
    end

    if #candidates < 1 then
        return nil
    end

    return candidates[math.random(1, #candidates)]
end

local function addItemToTheirOfferStack(itemId, itemType, amount, hideSeasonalTags)
    amount = tonumber(amount) or 1
    local sourceData = sync[itemType] and sync[itemType][itemId]
    local displayName = sourceData and (sourceData.ItemName or sourceData.Name) or itemId
    local rarity = sourceData and sourceData.Rarity or ""
    local stackKey = table.concat({
        tostring(itemType),
        tostring(rarity),
        normalizeItemText(displayName),
    }, ":")

    for _, offer in ipairs(theirOffer) do
        local offerData = sync[offer.ItemType] and sync[offer.ItemType][offer.ItemID]
        local offerName = offerData and (offerData.ItemName or offerData.Name) or offer.ItemID
        local offerRarity = offerData and offerData.Rarity or ""
        local offerStackKey = offer.StackKey or table.concat({
            tostring(offer.ItemType),
            tostring(offerRarity),
            normalizeItemText(offerName),
        }, ":")

        if (offer.ItemID == itemId and offer.ItemType == itemType)
            or offerStackKey == stackKey then
            offer.Amount = (tonumber(offer.Amount) or 1) + amount
            offer.HideSeasonalTags = offer.HideSeasonalTags or hideSeasonalTags == true
            offer.StackKey = stackKey
            return true
        end
    end

    if #theirOffer >= 4 then
        return false
    end

    table.insert(theirOffer, {
        ItemID = itemId,
        Amount = amount,
        ItemType = itemType,
        StackKey = stackKey,
        HideSeasonalTags = hideSeasonalTags == true,
    })

    return true
end

local function addRandomGodlyToTheirOffer()
    if not Runtime.tradeOpen() then
        warn("[IncomingTradePopup] Open the placeholder trade before adding their random godly.")
        return
    end

    local item = getRandomGodlyWeapon()
    if not item then
        warn("[IncomingTradePopup] No godly knife/gun found in the item database.")
        return
    end

    if not addItemToTheirOfferStack(item.ItemID, item.ItemType, item.Amount or 1) then
        warn("[IncomingTradePopup] Their offer is full.")
        return
    end

    drawOfferSlots(tradeModule.GUI.TheirOffer, theirOffer)
    resetAcceptUi()
    tradeModule.GUI.TheirOffer.Username.Text = "(" .. getFakeTradeSenderName() .. ")"
    CartiHubApplyPendingFakeTradeUsername()
    startAcceptCooldown(6)

end

local function getStoredWeaponValue(itemId, data)
    local displayName = data and (data.ItemName or data.Name) or itemId
    local values = isChromaWeapon(itemId, data)
        and _G.CartiHubChromaItemValues
        or _G.CartiHubNormalItemValues

    if type(values) ~= "table" then
        return 0
    end

    return tonumber(
        values[itemId]
        or values[displayName]
        or values[normalizeItemText(itemId)]
        or values[normalizeItemText(displayName)]
    ) or 0
end

local function addRandomWeaponAboveValue(minimumValue)
    if not Runtime.tradeOpen() then
        warn("[Carti Hub] Open a fake trade before adding an offer item.")
        return false
    end

    local candidates = {}
    for _, itemType in ipairs({ "Weapons", "Item" }) do
        for itemId, data in pairs(sync[itemType] or {}) do
            if type(data) == "table"
                and (data.Rarity == "Godly" or data.Rarity == "Ancient")
                and canFakeTradeItem(itemId, itemType)
                and getStoredWeaponValue(itemId, data) > minimumValue then
                table.insert(candidates, {
                    ItemID = itemId,
                    ItemType = itemType,
                })
            end
        end
    end

    if #candidates == 0 then
        warn("[Carti Hub] No tradeable weapons above value " .. tostring(minimumValue) .. " were found.")
        return false
    end

    local item = candidates[math.random(1, #candidates)]
    addSpecificItemToTheirOffer(item.ItemID, item.ItemType, true)
    return true
end

addSpecificItemToTheirOffer = function(itemId, itemType, hideSeasonalTags)
    if not Runtime.tradeOpen() then
        warn("[IncomingTradePopup] Open the placeholder trade before adding an offer-spawner item.")
        return
    end

    local itemData = sync[itemType] and sync[itemType][itemId]
    if not itemData then
        warn(("[IncomingTradePopup] Offer-spawner item not found: %s/%s"):format(tostring(itemType), tostring(itemId)))
        return
    end

    if not canFakeTradeItem(itemId, itemType) then
        warn(("[IncomingTradePopup] %s/%s is not tradeable."):format(tostring(itemType), tostring(itemId)))
        return
    end

    if not addItemToTheirOfferStack(itemId, itemType, 1, hideSeasonalTags) then
        warn("[IncomingTradePopup] Their offer is full.")
        return
    end

    drawOfferSlots(tradeModule.GUI.TheirOffer, theirOffer)
    resetAcceptUi()
    tradeModule.GUI.TheirOffer.Username.Text = "(" .. getFakeTradeSenderName() .. ")"
    CartiHubApplyPendingFakeTradeUsername()
    startAcceptCooldown(6)

end

removeLastTheirOffer = function()
    if not Runtime.tradeOpen() then
        warn("[IncomingTradePopup] Open the placeholder trade before removing their item.")
        return
    end

    if #theirOffer < 1 then
        warn("[IncomingTradePopup] Their offer is already empty.")
        return
    end

    local removed = table.remove(theirOffer)
    drawOfferSlots(tradeModule.GUI.TheirOffer, theirOffer)
    resetAcceptUi()
    tradeModule.GUI.TheirOffer.Username.Text = "(" .. getFakeTradeSenderName() .. ")"
    CartiHubApplyPendingFakeTradeUsername()
    startAcceptCooldown(6)

end

local function addOverlayClickTarget(parent, itemId, itemType)
    if not parent or not parent:IsA("GuiObject") then
        return
    end

    local oldOverlay = parent:FindFirstChild("ClientPlaceholderTradeToggle")
    if oldOverlay then
        oldOverlay:Destroy()
    end

    local overlay = Instance.new("TextButton")
    overlay.Name = "ClientPlaceholderTradeToggle"
    overlay.BackgroundTransparency = 1
    overlay.BorderSizePixel = 0
    overlay.Text = ""
    overlay.Size = UDim2.fromScale(1, 1)
    overlay.Position = UDim2.fromScale(0, 0)
    overlay.ZIndex = parent.ZIndex + 100
    overlay.Parent = parent

    Runtime.connect(overlay.MouseButton1Click, function()
        toggleLocalOffer(itemId, itemType)
    end)
end

local function addActionOverlay(parent, callback)
    if not parent or not parent:IsA("GuiObject") then
        return
    end

    local oldOverlay = parent:FindFirstChild("ClientPlaceholderTradeActionOverlay")
    if oldOverlay then
        oldOverlay:Destroy()
    end

    local overlay = Instance.new("TextButton")
    overlay.Name = "ClientPlaceholderTradeActionOverlay"
    overlay.BackgroundTransparency = 1
    overlay.BorderSizePixel = 0
    overlay.Text = ""
    overlay.Size = UDim2.fromScale(1, 1)
    overlay.Position = UDim2.fromScale(0, 0)
    overlay.ZIndex = parent.ZIndex + 100
    overlay.Parent = parent
    Runtime.connect(overlay.MouseButton1Click, callback)
end

local function installTradeActionButtons()
    local actions = tradeModule.GUI.Actions
    if not actions then
        return
    end

    local accept = actions:FindFirstChild("Accept")
    local decline = actions:FindFirstChild("Decline")

    if accept then
        addActionOverlay(accept, CartiHubHandleFakeAcceptClick)
        addActionOverlay(accept:FindFirstChild("ActionButton"), CartiHubHandleFakeAcceptClick)

        local confirmButton = accept:FindFirstChild("Confirm")
            and accept.Confirm:FindFirstChild("ActionButton")
        addActionOverlay(confirmButton, function()
            if localAcceptMode == "Confirm" and time() - localConfirmStartedAt >= 0.4 then
                setLocalAcceptState("Waiting")
                scheduleOtherSideAccept()
            end
        end)

        local cancelButton = accept:FindFirstChild("Cancel")
            and accept.Cancel:FindFirstChild("ActionButton")
        addActionOverlay(cancelButton, resetAcceptUi)
    end

    if decline then
        addActionOverlay(decline:FindFirstChild("ActionButton"), function()
            tradeModule.GUI.TradeGUI.Enabled = false
            CartiHubEndFakeTradeSession()
            tradeModule.TradeInventory = nil
            restoreLocalOfferToInventory()
            table.clear(theirOffer)
            resetAcceptUi()
        end)
    end
end

local function installInventoryToggleButtons()
    if not Runtime.tradeOpen() then return end
    local tradeInventory = tradeModule.TradeInventory
    if not tradeInventory or not tradeInventory.Data then
        return
    end

    for itemType, categories in pairs(tradeInventory.Data) do
        for _, items in pairs(categories) do
            for itemId, entry in pairs(items) do
                local frame = entry.Frame
                local actionButton = frame
                    and frame:FindFirstChild("Container")
                    and frame.Container:FindFirstChild("ActionButton")

                if actionButton and actionButton:IsA("GuiObject") then
                    addOverlayClickTarget(actionButton, itemId, itemType)
                elseif frame and frame:IsA("GuiObject") then
                    addOverlayClickTarget(frame, itemId, itemType)
                end
            end
        end
    end
end

function CartiHubInstallFakeTradeSearchFilter()
    if _G.CartiHubFakeTradeSearchConnection then
        _G.CartiHubFakeTradeSearchConnection:Disconnect()
        _G.CartiHubFakeTradeSearchConnection = nil
    end

    local gui = tradeModule.GUI
    local searchText = gui
        and gui.TradeGUI
        and gui.TradeGUI:FindFirstChild("Container")
        and gui.TradeGUI.Container:FindFirstChild("Items")
        and gui.TradeGUI.Container.Items:FindFirstChild("Tabs")
        and gui.TradeGUI.Container.Items.Tabs:FindFirstChild("Search")
        and gui.TradeGUI.Container.Items.Tabs.Search:FindFirstChild("Container")
        and gui.TradeGUI.Container.Items.Tabs.Search.Container:FindFirstChild("SearchText")

    if not searchText or not searchText:IsA("TextBox") then
        return
    end

    local function applyFilter()
        local inventory = tradeModule.TradeInventory
        if not inventory or not inventory.Data then
            return
        end

        local query = tostring(searchText.Text or ""):lower()

        for _, itemTypeData in pairs(inventory.Data) do
            for _, entry in pairs(itemTypeData.Current or {}) do
                if entry.Frame then
                    local itemName = tostring(entry.Name or ""):lower()
                    entry.Frame.Visible = query == "" or itemName:find(query, 1, true) ~= nil
                end
            end
        end
    end

    _G.CartiHubFakeTradeSearchConnection = Runtime.connect(searchText:GetPropertyChangedSignal("Text"), applyFilter)
    applyFilter()
end

local function openTradeFrameFromAccept()
    local ready, reason = Runtime.tradeReady()
    if not ready then return false, reason end
    local tradeGui = tradeModule.GUI.TradeGUI
    local tradeContainer = tradeGui.Container
    local shouldAutoSearch = _G.CartiHubAutoTradeSearchPending == true
    local shouldAutoUpgradeOffer = _G.CartiHubAutoUpgradeOfferPending == true

    _G.CartiHubAutoTradeSearchPending = nil
    _G.CartiHubAutoUpgradeOfferPending = nil

    _G.CartiHubFakeTradeActive = true
    CartiHubStartFakeTradeFrameGuard()
    restoreLocalOfferToInventory()
    table.clear(theirOffer)
    resetAcceptUi()

    for _, categoryName in ipairs({ "Weapons", "Pets" }) do
        local category = tradeContainer.Items.Main:FindFirstChild(categoryName)
        if category and category:FindFirstChild("Items") and category.Items:FindFirstChild("Container") then
            for _, section in ipairs(category.Items.Container:GetChildren()) do
                local container = section:FindFirstChild("Container")
                if container then
                    container:ClearAllChildren()
                end
            end
        end
    end

    tradeModule.TradeInventory = inventoryModule.GenerateInventory(
        tradeContainer.Items,
        Runtime.Inventory.profile(),
        "Trading",
        tradeModule.GUI.ItemsLayout
    )

    tradeModule.ConnectOfferButtons(tradeModule.TradeInventory)
    CartiHubInstallFakeTradeSearchFilter()
    redrawLocalTrade()
    tradeModule.GUI.TheirOffer.Username.Text = "(" .. getFakeTradeSenderName() .. ")"
    CartiHubApplyPendingFakeTradeUsername()
    _G.CartiHubPendingFakeTradeUsername = nil
    tradeGui.Enabled = true
    task.defer(installInventoryToggleButtons)
    task.delay(0.5, installInventoryToggleButtons)
    installTradeActionButtons()
    CartiHubWakeAcceptActionButton()
    CartiHubEnforceFakeTradeFrame()
    task.defer(CartiHubWakeAcceptActionButton)
    task.defer(CartiHubEnforceFakeTradeFrame)

    if shouldAutoSearch then
        CartiHubStartAutoTradeOfferFill()
    end

    if shouldAutoUpgradeOffer then
        task.spawn(function()
            task.wait(math.random(50, 200) / 100)

            local count = math.random(1, 3)
            for _ = 1, count do
                if not _G.CartiHubFakeTradeActive or not tradeGui.Enabled then
                    return
                end

                addRandomWeaponAboveValue(1000)
                task.wait(math.random(50, 200) / 100)
            end
        end)
    end
end

cleanupOldOverlays()

function CartiHubLaunchInstantFakePersonTrade(username, isReturnTrade, autoSearch, autoUpgradeOffer)
    if not Runtime.Active or _G.CartiHubFakeTradeActive or Runtime.TradeStarting then
        return false, "A fake trade is already open or the hub is closed."
    end

    local ready, reason = Runtime.tradeReady()
    if not ready then
        Runtime.resetTradePending()
        Runtime.Status.Trade = reason
        warn("[Carti Hub] " .. reason)
        return false, reason
    end
    if tradeModule.GUI.TradeGUI.Enabled then return false, "Another trade is already open." end
    Runtime.TradeStarting = true

    username = CartiHubNormalizeTradeUsername(username) or pickFakeTradeSenderName()
    currentFakeTradeSenderName = username
    _G.CartiHubAutoTradeSearchPending = autoSearch == true
    _G.CartiHubAutoUpgradeOfferPending = autoUpgradeOffer == true
    _G.CartiHubPendingFakeTradeUsername = username
    _G.CartiHubActiveFakeTradeUsername = username
    _G.CartiHubInstantFakeTradeReturnPending = isReturnTrade ~= true

    local ok, result, detail = xpcall(openTradeFrameFromAccept, debug.traceback)
    Runtime.TradeStarting = false
    if not ok or result == false then
        Runtime.Status.Trade = tostring(ok and detail or result)
        CartiHubEndFakeTradeSession()
        Runtime.resetTradePending()
        pcall(restoreLocalOfferToInventory)
        table.clear(theirOffer)
        tradeModule.TradeInventory = nil
        pcall(function() tradeModule.GUI.TradeGUI.Enabled = false end)
        warn("[Carti Hub] Trade could not open: " .. Runtime.Status.Trade)
        return false, Runtime.Status.Trade
    end
    Runtime.Status.Trade = nil
    return true
end

function CartiHubLaunchFakeUpgradeFakePlayer()
    return CartiHubLaunchInstantFakePersonTrade(nil, false, false, true)
end

function CartiHubLaunchUpgradeFakeTrade(username)
    if not username or username == "" then
        return false
    end

    return CartiHubLaunchInstantFakePersonTrade(username, true)
end

Runtime.connect(StartTradeBtn.MouseButton1Click, function()
    local ok, reason = CartiHubLaunchInstantFakePersonTrade(nil, true)
    if not ok then
        local original = StartTradeBtn.Text
        StartTradeBtn.Text = tostring(reason or "TRADE UNAVAILABLE")
        task.delay(3, function() if StartTradeBtn.Parent then StartTradeBtn.Text = original end end)
    end
end)
Runtime.connect(AddRandomBtn.MouseButton1Click, addRandomGodlyToTheirOffer)
Runtime.connect(RemoveLastBtn.MouseButton1Click, removeLastTheirOffer)

local function SwitchTab(activeBtn, activeFrame)
    SpawnerFrame.Visible = false
    TradeFrame.Visible = false
    UpgradingFrame.Visible = false
    BlockFrame.Visible = false
    SettingsFrame.Visible = false
    KeybindsFrame.Visible = false
    Runtime.NPCFrame.Visible = false

    for _, tab in ipairs({ SpawnerTabBtn, TradeTabBtn, UpgradingTabBtn, BlockTabBtn, SettingsTabBtn, KeybindsTabBtn, Runtime.NPCTab }) do
        tab.BackgroundColor3 = Color3.fromRGB(19, 7, 33)
        tab.BackgroundTransparency = 1
        tab.TextColor3 = Color3.fromRGB(182, 160, 203)

        local accent = tab:FindFirstChild("NebulaActiveAccent")
        if accent then
            accent.Visible = false
        end
    end

    activeFrame.Visible = true
    activeBtn.BackgroundColor3 = BUTTON_HOVER_COLOR
    activeBtn.BackgroundTransparency = 0.35
    activeBtn.TextColor3 = Color3.fromRGB(255, 244, 255)

    local activeAccent = activeBtn:FindFirstChild("NebulaActiveAccent")
    if activeAccent then
        activeAccent.Visible = true
    end
end

-- BEGIN MOBILE UI
-- All resizing stays inside the hub's safe-area canvases. Gameplay UI is untouched.
function Runtime.createUIResizeController(options)
    options = options or {}
    local ui = {Active = true, Records = {}, Hosts = {}, Connections = {}, Scale = options.Scale or 1,
        Compact = options.Compact, GetArea = options.GetArea, GetTouch = options.GetTouch, Save = options.Save}
    local function connect(signal, callback)
        local connection = Runtime.connect(signal, callback)
        table.insert(ui.Connections, connection)
        return connection
    end
    function ui:IsCompact(area)
        if self.Compact ~= nil then return self.Compact end
        local touch = self.GetTouch and self.GetTouch() or (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
        return touch or area.X < 600 or area.Y < 480
    end
    function ui:Measure(area, base, compact)
        local available = Vector2.new(math.max(1, area.X - 24), math.max(1, area.Y - 24))
        local height = compact and math.min(base.Y, math.max(200, available.Y * .88)) or base.Y
        local scale = compact and self.Scale or 1
        scale = math.min(scale, available.Y / height, available.X / math.min(base.X, 280))
        scale = math.max(.05, scale)
        return Vector2.new(math.min(base.X, available.X / scale), height), scale
    end
    function ui:Area(host)
        return self.GetArea and self.GetArea(host) or host.AbsoluteSize
    end
    function ui:Clamp(record, center)
        local area, size = self:Area(record.Host), record.Size * record.Scale.Scale
        local half = size / 2
        center = center or Vector2.new(record.Root.Position.X.Scale * area.X + record.Root.Position.X.Offset,
            record.Root.Position.Y.Scale * area.Y + record.Root.Position.Y.Offset)
        center = Vector2.new(math.clamp(center.X, half.X + 12, math.max(half.X + 12, area.X - half.X - 12)),
            math.clamp(center.Y, half.Y + 12, math.max(half.Y + 12, area.Y - half.Y - 12)))
        record.Root.Position = UDim2.fromScale(center.X / math.max(1, area.X), center.Y / math.max(1, area.Y))
    end
    function ui:Host(gui)
        if self.Hosts[gui] then return self.Hosts[gui] end
        gui.IgnoreGuiInset = false
        pcall(function()
            gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
            gui.SafeAreaCompatibility = Enum.SafeAreaCompatibility.None
            gui.ClipToDeviceSafeArea = true
        end)
        local host = Instance.new('Frame')
        host.Name, host.BackgroundTransparency, host.BorderSizePixel = 'CartiHubSafeCanvas', 1, 0
        host.Size, host.Parent = UDim2.fromScale(1, 1), gui
        self.Hosts[gui] = host
        connect(host:GetPropertyChangedSignal('AbsoluteSize'), function() self:Refresh() end)
        return host
    end
    function ui:BindDrag(record, handle)
        if not handle then return end
        handle.Active = true
        local pointer, start, center
        connect(handle.InputBegan, function(input)
            if pointer or not record.Root.Visible then return end
            if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            pointer, start = input, Vector2.new(input.Position.X, input.Position.Y)
            local area = self:Area(record.Host)
            center = Vector2.new(record.Root.Position.X.Scale * area.X, record.Root.Position.Y.Scale * area.Y)
        end)
        connect(UserInputService.InputChanged, function(input)
            if not pointer then return end
            if input ~= pointer and not (pointer.UserInputType == Enum.UserInputType.MouseButton1 and input.UserInputType == Enum.UserInputType.MouseMovement) then return end
            self:Clamp(record, center + Vector2.new(input.Position.X, input.Position.Y) - start)
        end)
        connect(UserInputService.InputEnded, function(input) if input == pointer then pointer = nil end end)
    end
    function ui:Register(root, config)
        config = config or {}
        local gui = config.Gui or root:FindFirstAncestorWhichIsA('ScreenGui')
        local record = {Root = root, Host = config.Host or self:Host(gui), Base = config.Base or Vector2.new(root.Size.X.Offset, root.Size.Y.Offset), Layout = config.Layout}
        local constraint = root:FindFirstChildOfClass('UISizeConstraint')
        if constraint then constraint:Destroy() end
        local aspect = root:FindFirstChildOfClass('UIAspectRatioConstraint')
        if aspect then aspect:Destroy() end
        record.Scale = root:FindFirstChildOfClass('UIScale') or Instance.new('UIScale', root)
        record.Scale.Name = 'CartiHubResponsiveScale'
        root.Draggable, root.AnchorPoint, root.Parent = false, Vector2.new(.5, .5), record.Host
        root.Position = UDim2.fromScale(config.CenterX or .5, .5)
        table.insert(self.Records, record)
        self:BindDrag(record, config.DragHandle)
        connect(root:GetPropertyChangedSignal('Visible'), function() if root.Visible then self:Refresh() end end)
        self:Refresh()
        return record
    end
    function ui:Refresh()
        if not self.Active then return end
        for _, record in ipairs(self.Records) do
            if record.Root.Parent then
                local area = self:Area(record.Host)
                if area.X > 1 and area.Y > 1 then
                    local compact = self:IsCompact(area)
                    record.Size, record.Scale.Scale = self:Measure(area, record.Base, compact)
                    record.Root.Size = UDim2.fromOffset(record.Size.X, record.Size.Y)
                    record.Compact = compact
                    if record.Layout then record.Layout(compact, record.Size, record.Scale.Scale) end
                    self:Clamp(record)
                end
            end
        end
        if self.Changed then self.Changed() end
    end
    function ui:SetScale(value, persist)
        value = tonumber(value)
        if not value or value ~= value or math.abs(value) == math.huge then return false end
        self.Scale = math.clamp(math.floor(value * 100 + .5) / 100, .65, 1.25)
        self:Refresh()
        if persist ~= false and self.Save then self.Save(self.Scale) end
        return true
    end
    function ui:Destroy()
        if not self.Active then return end
        self.Active = false
        for _, connection in ipairs(self.Connections) do connection:Disconnect(); Runtime.Connections[connection] = nil end
        for _, record in ipairs(self.Records) do if record.Root.Parent then record.Root:Destroy() end end
        for _, host in pairs(self.Hosts) do host:Destroy() end
        table.clear(self.Records); table.clear(self.Hosts); table.clear(self.Connections)
    end
    Runtime.cleanup(function() ui:Destroy() end)
    return ui
end

Runtime.setupResponsiveUI = function()
    local preference = tonumber(_G.CartiHubMobileUIScale) or 1
    if type(readfile) == 'function' then
        local ok, data = pcall(function() return game.HttpService:JSONDecode(readfile('cartihub-mm2-mobile-ui.json')) end)
        if ok and type(data) == 'table' and type(data.Scale) == 'number' then preference = data.Scale end
    end
    local ui = Runtime.createUIResizeController({Save = function(value)
        _G.CartiHubMobileUIScale = value
        if type(writefile) == 'function' then pcall(writefile, 'cartihub-mm2-mobile-ui.json', game.HttpService:JSONEncode({Scale = value})) end
    end})
    ui:SetScale(preference, false)
    Runtime.ResponsiveUI = ui
    local pages = {SpawnerFrame, TradeFrame, UpgradingFrame, BlockFrame, SettingsFrame, KeybindsFrame, Runtime.NPCFrame}
    local tabs = {SpawnerTabBtn, TradeTabBtn, UpgradingTabBtn, BlockTabBtn, SettingsTabBtn, KeybindsTabBtn, Runtime.NPCTab}
    local originals = setmetatable({}, {__mode = 'k'})
    local function stylePage(page, compact)
        for _, item in ipairs(page:GetDescendants()) do
            if item:IsA('TextButton') or item:IsA('TextBox') then
                if not originals[item] then originals[item] = {Size = item.Size, TextSize = item.TextSize} end
                local saved = originals[item]
                item.TextSize = compact and math.max(13, saved.TextSize) or saved.TextSize
                if item.Parent == page and saved.Size.Y.Scale == 0 then
                    item.Size = UDim2.new(saved.Size.X.Scale, saved.Size.X.Offset, 0, compact and math.max(44, saved.Size.Y.Offset) or saved.Size.Y.Offset)
                end
            end
        end
    end
    function ui:LayoutTabs(compact, fallback)
        TabContainer.ScrollingEnabled = compact
        TabContainer.ScrollingDirection = Enum.ScrollingDirection.X
        TabContainer.ScrollBarThickness = compact and 2 or 0
        if compact then
            TabLayout.FillDirection, TabLayout.FillDirectionMaxCells = Enum.FillDirection.Horizontal, 7
            TabLayout.CellSize, TabLayout.CellPadding = UDim2.fromOffset(82, 42), UDim2.fromOffset(4, 0)
            TabContainer.CanvasSize = UDim2.fromOffset(7 * 86, 0)
        else
            TabContainer.CanvasPosition, TabContainer.CanvasSize = Vector2.zero, UDim2.new()
            TabLayout.FillDirectionMaxCells = fallback and 1 or 7
            TabLayout.CellSize = fallback and UDim2.new(1, -8, 0, 38) or UDim2.new(1 / 7, -4, 1, 0)
            TabLayout.CellPadding = fallback and UDim2.fromOffset(0, 4) or UDim2.fromOffset(4, 0)
        end
        for _, tab in ipairs(tabs) do tab.TextSize = compact and 13 or (fallback and 10 or 8) end
        for _, page in ipairs(pages) do stylePage(page, compact) end
    end
    local pendingStyle = {}
    for _, page in ipairs(pages) do
        if page ~= Runtime.NPCFrame then page.AutomaticCanvasSize, page.CanvasSize = Enum.AutomaticSize.Y, UDim2.new() end
        Runtime.connect(page.DescendantAdded, function()
            if pendingStyle[page] then return end
            pendingStyle[page] = true
            task.defer(function()
                pendingStyle[page] = nil
                if ui.Active then stylePage(page, ui:IsCompact(ui:Area(ui:Host(SakaUI)))) end
            end)
        end)
    end
    local sizeRow = Instance.new('Frame')
    sizeRow.Name, sizeRow.Size, sizeRow.BackgroundTransparency, sizeRow.LayoutOrder = 'MobileUISizeControls', UDim2.new(1, 0, 0, 96), 1, -100
    sizeRow.BackgroundColor3, sizeRow.Parent = BUTTON_COLOR, SettingsFrame
    Instance.new('UICorner', sizeRow).CornerRadius = UDim.new(0, 5)
    local caption = Instance.new('TextLabel')
    caption.Name, caption.Size, caption.Position = 'MobileUISizeLabel', UDim2.new(1, -16, 0, 26), UDim2.fromOffset(8, 0)
    caption.BackgroundTransparency, caption.TextColor3, caption.Font, caption.TextSize = 1, Color3.fromRGB(242, 231, 255), Enum.Font.GothamBold, 13
    caption.Parent = sizeRow
    local function button(name, text, x, width, callback)
        local item = Instance.new('TextButton')
        item.Name, item.Text, item.Size, item.Position = name, text, UDim2.new(width, -4, 0, 44), UDim2.new(x, 2, 0, 28)
        item.BackgroundColor3, item.TextColor3, item.Font, item.TextSize = BUTTON_HOVER_COLOR, Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold, 14
        item.Parent = sizeRow
        Instance.new('UICorner', item).CornerRadius = UDim.new(0, 5)
        Runtime.connect(item.Activated, callback)
        return item
    end
    button('MobileUISmaller', '-', 0, .17, function() ui:SetScale(ui.Scale - .05) end)
    local box = Instance.new('TextBox')
    box.Name, box.Size, box.Position = 'MobileUISizeValue', UDim2.new(.29, -4, 0, 44), UDim2.new(.17, 2, 0, 28)
    box.BackgroundColor3, box.TextColor3, box.Font, box.TextSize = Color3.fromRGB(20, 8, 34), Color3.fromRGB(242, 231, 255), Enum.Font.GothamBold, 14
    box.ClearTextOnFocus, box.Parent = false, sizeRow
    button('MobileUILarger', '+', .46, .17, function() ui:SetScale(ui.Scale + .05) end)
    button('MobileUIAuto', 'Reset', .63, .37, function() ui:SetScale(1) end)
    local hint = Instance.new('TextLabel')
    hint.Size, hint.Position, hint.BackgroundTransparency = UDim2.new(1, -16, 0, 20), UDim2.fromOffset(8, 75), 1
    hint.Text, hint.TextColor3, hint.Font, hint.TextSize = '65–125% · saved on this device', Color3.fromRGB(210, 192, 230), Enum.Font.Gotham, 11
    hint.Parent = sizeRow
    function ui.Changed()
        caption.Text = 'Mobile UI size: ' .. math.floor(ui.Scale * 100 + .5) .. '%'
        if not box:IsFocused() then box.Text = tostring(math.floor(ui.Scale * 100 + .5)) .. '%' end
    end
    Runtime.connect(box.FocusLost, function()
        local value = tonumber((box.Text:gsub('%%', '')))
        if value then ui:SetScale(value / 100) end
        box.Text = tostring(math.floor(ui.Scale * 100 + .5)) .. '%'
    end)
    function ui:OpenSizeControls()
        SwitchTab(SettingsTabBtn, SettingsFrame)
        SettingsFrame.CanvasPosition = Vector2.zero
        if TabContainer.ScrollingEnabled then
            -- Settings should remain visible when opened from the topbar shortcut.
            local scale = Runtime.uiCanvasHeight(TabLayout) > 0 and TabLayout.AbsoluteContentSize.Y / Runtime.uiCanvasHeight(TabLayout) or 1
            local x = (SettingsTabBtn.AbsolutePosition.X - TabContainer.AbsolutePosition.X) / scale + TabContainer.CanvasPosition.X
            TabContainer.CanvasPosition = Vector2.new(math.max(0, x - 8), 0)
        end
    end
    function ui:AddSizeButton(parent)
        local item = Instance.new('TextButton')
        item.Name, item.Text, item.BackgroundTransparency = 'CartiHubUISize', 'Size', 1
        item.Size, item.Position = UDim2.new(0, 46, 1, 0), UDim2.new(1, -96, 0, 0)
        item.TextColor3, item.Font, item.TextSize, item.ZIndex = Color3.fromRGB(231, 222, 242), Enum.Font.GothamBold, 13, 23
        item.Parent = parent
        Runtime.connect(item.Activated, function() self:OpenSizeControls() end)
        return item
    end
    local fallbackSize = ui:AddSizeButton(MainFrame)
    fallbackSize.Size, fallbackSize.Position = UDim2.fromOffset(46, 44), UDim2.new(1, -96, 0, 0)
    ui:Register(MainFrame, {Base = Vector2.new(448, 540), CenterX = .78, DragHandle = Title, Layout = function(compact)
        if not MainFrame.Visible then return end
        ui:LayoutTabs(compact, true)
        fallbackSize.Visible = compact
        local wrapper = MainFrame:FindFirstChild('CartiHubNebulaWrapper')
        if wrapper then
            for _, name in ipairs({'NebulaRibbon', 'NebulaProfile'}) do local part = wrapper:FindFirstChild(name) or MainFrame:FindFirstChild(name); if part then part.Visible = not compact end end
            local topbar = wrapper:FindFirstChild('NebulaTopbar'); if topbar then topbar.Size = UDim2.new(1, 0, 0, compact and 44 or 34) end
            local canvas = wrapper:FindFirstChild('NebulaPageCanvas')
            if canvas then canvas.Size, canvas.Position = compact and UDim2.new(1, -16, 1, -98) or UDim2.new(1, -122, 1, -46), UDim2.fromOffset(compact and 8 or 116, compact and 94 or 40) end
        end
        local caption = MainFrame:FindFirstChild('NebulaPageCaption'); if caption then caption.Visible = not compact end
        Title.Size, Title.Position = compact and UDim2.new(1, -120, 0, 44) or UDim2.new(1, -154, 0, 34), UDim2.fromOffset(compact and 12 or 112, 0)
        CloseBtn.Size, CloseBtn.Position = UDim2.fromOffset(compact and 44 or 28, compact and 44 or 28), UDim2.new(1, compact and -46 or -34, 0, compact and 0 or 3)
        TabContainer.Size, TabContainer.Position = compact and UDim2.new(1, -16, 0, 44) or UDim2.new(0, 100, 1, -128), UDim2.fromOffset(compact and 8 or 8, compact and 44 or 76)
        for _, page in ipairs(pages) do page.Size, page.Position = compact and UDim2.new(1, -24, 1, -102) or UDim2.new(1, -128, 1, -62), UDim2.fromOffset(compact and 12 or 116, compact and 94 or 50) end
    end})
    for _, root in ipairs({SpawnerGuiFrame, OfferSpawnerGuiFrame, RealisticSpawnerGuiFrame, SakaUI:FindFirstChild('AvatarChangerGUI')}) do
        if root then
            local base = Vector2.new(root.Size.X.Offset, root.Size.Y.Offset)
            local header = root:FindFirstChildWhichIsA('TextLabel')
            ui:Register(root, {Base = base, DragHandle = header, Layout = function(compact, size, scale)
                for _, scroll in ipairs(root:GetChildren()) do
                    if scroll:IsA('ScrollingFrame') then
                        local grid = scroll:FindFirstChildOfClass('UIGridLayout')
                        if grid then
                            grid.FillDirectionMaxCells = math.max(1, math.floor((size.X - 15) / 83))
                            scroll.CanvasSize = UDim2.fromOffset(0, Runtime.uiCanvasHeight(grid) + 10)
                        end
                    end
                end
            end})
        end
    end
    ui:Refresh()
end
Runtime.setupResponsiveUI()
Runtime.setupResponsiveUI = nil
-- END MOBILE UI

-- BEGIN NPC UI
Runtime.buildNPCUI = function()
    local npc = Runtime.NPC
    local page = Runtime.NPCFrame
    page.Name, page.AutomaticCanvasSize, page.CanvasSize = "NPCPage", Enum.AutomaticSize.Y, UDim2.new()
    local function label(name, text, height, order)
        local item = Instance.new("TextLabel")
        item.Name,item.Text,item.Size,item.LayoutOrder = name,text,UDim2.new(1,-4,0,height),order
        item.BackgroundTransparency,item.TextWrapped,item.Font,item.TextSize = 1,true,Enum.Font.Gotham,11
        item.TextColor3,item.TextXAlignment,item.Parent = Color3.fromRGB(211,193,229),Enum.TextXAlignment.Left,page
        return item
    end
    local function button(name,text,order,fn)
        local item = CreateBtn(page,text)
        item.Name,item.LayoutOrder,item.Size = name,order,UDim2.new(1,0,0,30)
        Runtime.connect(item.MouseButton1Click,fn)
        return item
    end
    label("NPCIntro","Local NPCs · individual movement, gestures, outfits & bubble chat. Visible only to you.",36,1)
    local status = label("NPCStatus","0 / 20 NPCs",20,2)
    local count = CreateBox(page,"Group size (1–20)")
    count.Name,count.LayoutOrder,count.Text,count.ClearTextOnFocus = "NPCCount",3,"5",false
    local avatar = CreateBox(page,"Avatar username / ID (blank = mixed)")
    avatar.Name,avatar.LayoutOrder,avatar.ClearTextOnFocus = "NPCAvatar",4,false
    local name = CreateBox(page,"NPC name (optional)")
    name.Name,name.LayoutOrder,name.ClearTextOnFocus = "NPCName",5,false
    local spawn
    spawn=button("NPCSpawn","SPAWN GROUP",6,function()
        local amount=tonumber(count.Text)
        if not amount or amount%1~=0 or amount<1 or amount>20 then status.Text="Enter a whole group size from 1 to 20.";return end
        local ok,reason=npc:SpawnGroup(amount,avatar.Text,name.Text)
        if not ok then status.Text=reason end
    end)
    local mode
    mode=button("NPCMode","MOVEMENT: FOLLOW",7,function()
        local nextMode={Follow="Roam",Roam="Stay",Stay="Follow"}
        npc:SetMode(nextMode[npc.Mode]);mode.Text="MOVEMENT: "..npc.Mode:upper()
    end)
    local pause
    pause=button("NPCPause","PAUSE MOVEMENT",8,function()
        npc:SetPaused(not npc.Paused);pause.Text=npc.Paused and "RESUME MOVEMENT" or "PAUSE MOVEMENT"
    end)
    local spread=CreateBox(page,"Follow spacing in studs (6–22)")
    spread.Name,spread.LayoutOrder,spread.Text,spread.ClearTextOnFocus="NPCSpread",9,"9",false
    Runtime.connect(spread.FocusLost,function()
        npc.Spread=math.clamp(tonumber(spread.Text) or npc.Spread,6,22);spread.Text=tostring(npc.Spread)
    end)
    local chat
    chat=button("NPCChat","BUBBLE CHAT: ON",10,function()
        npc:SetChat(not npc.ChatEnabled);chat.Text=npc.ChatEnabled and "BUBBLE CHAT: ON" or "BUBBLE CHAT: OFF"
    end)
    local names
    names=button("NPCNames","NAME TAGS: ON",11,function()
        npc.NamesEnabled=not npc.NamesEnabled
        for _,record in pairs(npc.Records) do record.Humanoid.NameDisplayDistance=npc.NamesEnabled and 45 or 0 end
        names.Text=npc.NamesEnabled and "NAME TAGS: ON" or "NAME TAGS: OFF"
    end)
    button("NPCRecall","BRING GROUP HERE",12,function() if not npc:Recall() then status.Text="Wait for your character to spawn." end end)
    label("NPCRosterTitle","SELECT AN NPC",18,13)
    local roster=Instance.new("ScrollingFrame")
    roster.Name,roster.Size,roster.LayoutOrder="NPCRoster",UDim2.new(1,0,0,112),14
    roster.BackgroundColor3,roster.BorderSizePixel=Color3.fromRGB(20,8,34),0
    roster.ScrollBarThickness,roster.AutomaticCanvasSize,roster.CanvasSize=3,Enum.AutomaticSize.Y,UDim2.new()
    roster.Parent=page
    Instance.new("UICorner",roster).CornerRadius=UDim.new(0,5)
    local list=Instance.new("UIListLayout",roster);list.SortOrder=Enum.SortOrder.LayoutOrder;list.Padding=UDim.new(0,3)
    local rows={}
    local selected=label("NPCSelected","Select a spawned NPC to speak, wave or remove it.",28,15)
    local message=CreateBox(page,"Local bubble message (up to 140 characters)")
    message.Name,message.LayoutOrder,message.ClearTextOnFocus="NPCMessage",16,false
    button("NPCSpeak","SPEAK · SELECTED NPC",17,function()
        if not npc.Selected then status.Text="Select an NPC in the list first."
        elseif not npc.ChatEnabled then status.Text="Turn bubble chat on first."
        elseif not npc:Say(npc.Selected,message.Text) then status.Text="Enter a message first." end
    end)
    local wave=button("NPCWave","WAVE · SELECTED NPC",18,function()
        local gesture=npc.Selected and npc.Selected.SelectedGesture or "Wave"
        if not npc:Emote(npc.Selected,gesture) then status.Text="Select a loaded NPC with animations on first." end
    end)
    button("NPCRemove","REMOVE SELECTED",19,function() npc:Remove(npc.Selected) end)
    button("NPCClear","CLEAR ALL / CANCEL LOADING",20,function() npc:Clear() end)
    -- Keep numeric inputs understandable after their placeholders disappear.
    for _,child in ipairs(page:GetChildren()) do
        if child:IsA("GuiObject") and child.LayoutOrder>=3 then child.LayoutOrder+=1 end
    end
    label("NPCCountLabel","GROUP SIZE · 1–20",16,3)
    for _,child in ipairs(page:GetChildren()) do
        if child:IsA("GuiObject") and child.LayoutOrder>=10 then child.LayoutOrder+=1 end
    end
    label("NPCSpreadLabel","FOLLOW SPACING · 6–22 STUDS",16,10)
    wave.LayoutOrder=25
    page.NPCRemove.LayoutOrder,page.NPCClear.LayoutOrder=34,35
    label("NPCIndividualTitle","SELECTED NPC · INDIVIDUAL CONTROLS",18,20)
    local individualMode=button("NPCIndividualMode","MOVEMENT: USE GROUP SETTING",21,function()
        local record=npc.Selected
        if not record then status.Text="Select an NPC first.";return end
        local nextMode={Group="Follow",Follow="Roam",Roam="Stay",Stay="Group"}
        npc:SetRecordMode(record,nextMode[record.ModeOverride or "Group"])
    end)
    local individualPause=button("NPCIndividualPause","PAUSE SELECTED NPC",22,function()
        if not npc.Selected then status.Text="Select an NPC first.";return end
        npc:SetRecordPaused(npc.Selected,not npc.Selected.Paused)
    end)
    local animations=button("NPCAnimations","ANIMATIONS: ON",23,function()
        if not npc.Selected then status.Text="Select an NPC first.";return end
        npc:SetAnimations(npc.Selected,not npc.Selected.AnimationsEnabled)
    end)
    local gesture=button("NPCGesture","GESTURE: WAVE",24,function()
        local record=npc.Selected
        if not record then status.Text="Select an NPC first.";return end
        local nextGesture={Wave="Point",Point="Cheer",Cheer="Laugh",Laugh="Wave"}
        record.SelectedGesture=nextGesture[record.SelectedGesture or "Wave"]
        if npc.Changed then npc.Changed() end
    end)
    label("NPCLoadoutTitle","SELECTED NPC · KNIFE & GUN",18,26)
    local knife=CreateBox(page,"Knife name / item ID")
    knife.Name,knife.LayoutOrder,knife.Text,knife.ClearTextOnFocus="NPCKnife",27,"DefaultKnife",false
    local gun=CreateBox(page,"Gun name / item ID")
    gun.Name,gun.LayoutOrder,gun.Text,gun.ClearTextOnFocus="NPCGun",28,"DefaultGun",false
    button("NPCLoadout","APPLY KNIFE + GUN",29,function()
        if not npc.Selected then status.Text="Select an NPC first.";return end
        if not npc.SetLoadout then status.Text="Weapon visuals are still loading.";return end
        local ok,reason=npc:SetLoadout(npc.Selected,knife.Text,gun.Text)
        if not ok then status.Text=tostring(reason or "Could not load those weapons.") end
    end)
    local held=button("NPCHeld","WEAPONS: HOLSTERED",30,function()
        if not npc.Selected then status.Text="Select an NPC first.";return end
        if not npc.EquipWeapon then status.Text="Weapon visuals are still loading.";return end
        local loadout=npc:GetLoadout(npc.Selected) or {}
        local nextSlot={Holstered="Knife",Knife="Gun",Gun="Holstered"}
        local ok,reason=npc:EquipWeapon(npc.Selected,nextSlot[loadout.Equipped or "Holstered"])
        if not ok then status.Text=tostring(reason or "That weapon is unavailable.") end
    end)
    local autoWeapons=button("NPCAutoWeapons","AUTOMATIC EQUIPPING: ON",31,function()
        if not npc.Selected then status.Text="Select an NPC first.";return end
        if not npc.SetAutoWeapons then status.Text="Weapon visuals are still loading.";return end
        npc:SetAutoWeapons(npc.Selected,not npc.Selected.AutoWeapons)
    end)
    local pace=button("NPCChatPace","CHAT FREQUENCY: NORMAL",32,function()
        local nextPace={Quiet="Normal",Normal="Lively",Lively="Quiet"}
        npc:SetChatPace(nextPace[npc.ChatPace])
    end)
    local footsteps=button("NPCFootsteps","FOOTSTEP SOUNDS: ON",33,function()
        npc.FootstepsEnabled=not npc.FootstepsEnabled
        if not npc.FootstepsEnabled then for _,record in pairs(npc.Records) do if record.Footsteps then record.Footsteps:Stop() end end end
        if npc.Changed then npc.Changed() end
    end)
    local previousSelection
    npc.Changed=function()
        if not page.Parent then return end
        for id,row in pairs(rows) do if not npc.Records[id] then row:Destroy();rows[id]=nil end end
        for _,record in ipairs(npc:List()) do
            local row=rows[record.Id]
            if not row then
                row=CreateBtn(roster,"");row.Name="NPCRow_"..record.Id;row.Size=UDim2.new(1,-5,0,28)
                row.LayoutOrder,row.TextSize=record.Id,11;rows[record.Id]=row
                Runtime.connect(row.MouseButton1Click,function()
                    if not record.Disposed then npc.Selected=record;npc.Changed() end
                end)
            end
            row.Text=(npc.Selected==record and "› " or "")..record.Name.." · "..record.Profile.Name
            row.BackgroundColor3=npc.Selected==record and BUTTON_HOVER_COLOR or BUTTON_COLOR
        end
        status.Text=npc.LastError and ("Could not spawn: "..tostring(npc.LastError):match("[^\n]+"))
            or (tostring(npc:Count()).." / 20 NPCs"..(npc.PendingCount>0 and " · loading avatar…" or ""))
        selected.Text=npc.Selected and ("Selected: "..npc.Selected.Name.." · "..npc.Selected.Profile.Name.." · "..npc.Selected.AnimationSet.Name)
            or "Select a spawned NPC to speak, wave or remove it."
        spawn.Text=npc.Batch and "LOADING GROUP…" or "SPAWN GROUP"
        mode.Text="MOVEMENT: "..npc.Mode:upper()
        pause.Text=npc.Paused and "RESUME MOVEMENT" or "PAUSE MOVEMENT"
        chat.Text=npc.ChatEnabled and "BUBBLE CHAT: ON" or "BUBBLE CHAT: OFF"
        names.Text=npc.NamesEnabled and "NAME TAGS: ON" or "NAME TAGS: OFF"
        local record=npc.Selected
        individualMode.Text="MOVEMENT: "..(record and (record.ModeOverride or "Group"):upper() or "USE GROUP SETTING")
        individualPause.Text=record and record.Paused and "RESUME SELECTED NPC" or "PAUSE SELECTED NPC"
        animations.Text="ANIMATIONS: "..(record and not record.AnimationsEnabled and "OFF" or "ON")
        local selectedGesture=record and record.SelectedGesture or "Wave"
        gesture.Text="GESTURE: "..selectedGesture:upper();wave.Text=selectedGesture:upper().." · SELECTED NPC"
        local loadout=record and npc.GetLoadout and npc:GetLoadout(record) or {}
        held.Text="WEAPONS: "..tostring(loadout.Equipped or "Holstered"):upper()
        autoWeapons.Text="AUTOMATIC EQUIPPING: "..(record and record.AutoWeapons==false and "OFF" or "ON")
        pace.Text="CHAT FREQUENCY: "..npc.ChatPace:upper()
        footsteps.Text="FOOTSTEP SOUNDS: "..(npc.FootstepsEnabled and "ON" or "OFF")
        if record~=previousSelection then
            previousSelection=record
            if record then knife.Text=loadout.Knife or "DefaultKnife";gun.Text=loadout.Gun or "DefaultGun" end
        end
    end
    npc.Changed()
    Runtime.connect(Runtime.NPCTab.MouseButton1Click,function() SwitchTab(Runtime.NPCTab,page) end)
end
Runtime.buildNPCUI()
Runtime.buildNPCUI = nil
-- END NPC UI

Runtime.connect(SpawnerTabBtn.MouseButton1Click, function()
    SwitchTab(SpawnerTabBtn, SpawnerFrame)
end)

Runtime.connect(TradeTabBtn.MouseButton1Click, function()
    SwitchTab(TradeTabBtn, TradeFrame)
end)

Runtime.connect(UpgradingTabBtn.MouseButton1Click, function()
    CartiHubRefreshUpgradePlayerDropdown()
    SwitchTab(UpgradingTabBtn, UpgradingFrame)
end)

Runtime.connect(BlockTabBtn.MouseButton1Click, function()
    SwitchTab(BlockTabBtn, BlockFrame)
end)

Runtime.connect(SettingsTabBtn.MouseButton1Click, function()
    SwitchTab(SettingsTabBtn, SettingsFrame)
end)

Runtime.connect(KeybindsTabBtn.MouseButton1Click, function()
    SwitchTab(KeybindsTabBtn, KeybindsFrame)
end)

if _G.ClientPlaceholderTradeKeybindConnection then
    _G.ClientPlaceholderTradeKeybindConnection:Disconnect()
end

_G.ClientPlaceholderTradeKeybindConnection = Runtime.connect(UserInputService.InputBegan, function(input, gameProcessed)
    if UserInputService:GetFocusedTextBox() then
        return
    end

    if input.KeyCode == Enum.KeyCode.Six then
        if SakaUI and SakaUI.Parent then
            SakaUI.Enabled = not SakaUI.Enabled

            local nebulaGui = _G.CartiHubNebulaGui
            if nebulaGui and nebulaGui.Parent then
                nebulaGui.Enabled = SakaUI.Enabled
            end
        end
        return
    end

    if input.KeyCode == Enum.KeyCode.F then
        showRandomFakeFriendJoinNotification()
        return
    end

    if input.KeyCode == Enum.KeyCode.Two then
        addRandomWeaponAboveValue(200)
        return
    end

    if gameProcessed then
        return
    end

    if input.KeyCode == Enum.KeyCode.Z then
        CartiHubLaunchInstantFakePersonTrade(nil, true)
    elseif input.KeyCode == Enum.KeyCode.Y then
        addRandomGodlyToTheirOffer()
    elseif input.KeyCode == Enum.KeyCode.B then
        removeLastTheirOffer()
    end
end)

_G.CartiHubSpawnWeapon = spawnWeapon
_G.CartiHubSpawnWeaponById = spawnWeaponById
_G.CartiHubSpawnWeaponByIdNoPopup = spawnWeaponByIdNoPopup
_G.CartiHubSpawnAllGodlies = spawnAllGodlyWeapons
_G.CartiHubSpawnAllChromas = spawnAllChromaWeapons
_G.CartiHubSpawnAllAncients = spawnAllAncientWeapons
_G.CartiHubStartFakeTrade = function(autoSearch)
    return CartiHubLaunchInstantFakePersonTrade(nil, true, autoSearch == true)
end
_G.CartiHubLaunchUpgradeFakeTrade = CartiHubLaunchUpgradeFakeTrade
_G.CartiHubLaunchInstantFakePersonTrade = CartiHubLaunchInstantFakePersonTrade
_G.CartiHubSetAutoSelectLastTraded = CartiHubSetAutoSelectLastTraded
_G.CartiHubAddRandomTheirGodly = addRandomGodlyToTheirOffer
_G.CartiHubAddRandomWeaponAboveValue = addRandomWeaponAboveValue
_G.CartiHubRemoveLastTheirOffer = removeLastTheirOffer
_G.CartiHubPopulateWeaponSpawner = populateWeaponSpawner
_G.CartiHubPopulateOfferSpawner = populateOfferSpawner
_G.CartiHubPopulateRealisticSpawner = populateRealisticSpawner
_G.CartiHubAddWeaponBox = AddWeaponBox
_G.CartiHubWeaponVisuals = Runtime.Visual.Entries
_G.CartiHubApplyWeaponVisual = applyWeaponVisual
_G.CartiHubApplyEquippedWeaponVisuals = applyEquippedWeaponVisuals
_G.CartiHubShowFriendJoin = showFakeFriendJoinNotification
_G.CartiHubShowRandomFriendJoin = showRandomFakeFriendJoinNotification
_G.CartiHubSetAutoFriendJoin = setAutoFriendJoinEnabled
_G.CartiHubApplyAvatarFromUserId = applyAvatarFromUserId
_G.CartiHubApplyAvatar = applyAvatarFromUserId
_G.CartiHubResetAvatar = function()
    return applyAvatarFromUserId(localPlayer.UserId)
end

_G.CartiHubGetVisualStatus = function() return table.clone(Runtime.Visual.Status) end
_G.CartiHubRegisterWeaponModel = function(itemId, source)
    if not Runtime.Active then return false, "The hub is closed." end
    local data = Runtime.Visual.data(itemId)
    if not data or typeof(source) ~= "Instance" then return false, "Provide a canonical weapon ID and model instance." end
    local kind = Runtime.Visual.kind(data)
    if kind ~= "Gun" and kind ~= "Knife" then return false, "The item is not a weapon." end
    local model = Runtime.Visual.captureModel(source)
    if not model then return false, "The model has no usable weapon part." end
    if Runtime.Visual.Models[itemId] then Runtime.Visual.Models[itemId]:Destroy() end
    Runtime.Visual.Models[itemId] = model
    Runtime.Visual.Entries[itemId] = {Type = kind, Template = model, Chroma = data.Chroma == true,
        ChromaRoot = itemId == "TreeKnife2023Chroma",
        Placement = itemId == "IcecreamChroma" and "WaistLeft" or nil}
    Runtime.Visual.report(itemId, nil)
    return true
end
_G.CartiHubGetDisplayedInventory = Runtime.Inventory.profile
_G.CartiHubRefreshInventory = refreshMainInventoryNow
Runtime.cleanup(function()
    local wasFakeTrade = _G.CartiHubFakeTradeActive == true
    otherAcceptSequence += 1
    cooldownSequence += 1
    CartiHubEndFakeTradeSession()
    Runtime.resetTradePending()
    if wasFakeTrade then
        pcall(function() tradeModule.GUI.TradeGUI.Enabled = false end)
        tradeModule.TradeInventory = nil
    end
    table.clear(localOffer)
    table.clear(theirOffer)
    table.clear(Runtime.Inventory.Deltas)
    for _, state in ipairs({_G.CartiHubAutoTradeState or {}, _G.CartiHubBlockValueState or {},
        _G.CartiHubPlayerListBlockButtonState or {}}) do state.Enabled = false end
    _G.CartiHubPlayerListBlockButtonsEnabled = false
    _G.CartiHubNebulaGui = nil
    _G.CartiHubAutoTradeState = nil
    _G.CartiHubBlockValueState = nil
    _G.CartiHubPlayerListBlockButtonState = nil
    _G.CartiHubAvatarPersistenceState = nil
    _G.ClientPlaceholderTradeKeybindConnection = nil
    pcall(refreshMainInventoryNow)
end)

-- Add values here. Keys may be an item id, display name, or normalized name.
-- Keep chroma variants in the chroma table so they never use a normal value.
task.spawn(function()
    local NORMAL_ITEM_VALUES = {
        ["Gingerscope"] = 17750,
        ["Traveler's Axe"] = 8100,
        ["TravelersAxe"] = 8100,
        ["Celestial"] = 2175,
        ["VampireAxe"] = 1225,
        ["Harvester"] = 250,
        ["Icepiercer"] = 160,
        ["Traveler's Gun"] = 5600,
        ["TravelersGun"] = 5600,
        ["Evergun"] = 3450,
        ["Constellation"] = 2700,
        ["Evergreen"] = 2500,
        ["Turkey"] = 2450,
        ["Vampire's Gun"] = 1950,
        ["VampiresGun"] = 1950,
        ["Alienbeam"] = 1850,
        ["Darkshot"] = 1650,
        ["Darksword"] = 1625,
        ["Raygun"] = 1450,
        ["Blossom"] = 1310,
        ["Sakura"] = 1300,
        ["Sunrise"] = 1125,
        ["Snowcannon"] = 850,
        ["Bauble"] = 825,
        ["Sunset"] = 625,
        ["Soul"] = 615,
        ["Spirit"] = 605,
        ["Rainbow_G"] = 420,
        ["Flora"] = 410,
        ["Rainbow_K"] = 410,
        ["Bloom"] = 400,
        ["Heart Wand"] = 340,
        ["HeartWand"] = 340,
        ["Ocean"] = 285,
        ["Waves"] = 280,
        ["Xenoknife"] = 280,
        ["Xenoshot"] = 280,
        ["Flowerwood Gun"] = 265,
        ["FlowerwoodGun"] = 265,
        ["Blizzard"] = 260,
        ["Flowerwood"] = 260,
        ["Snowstorm"] = 260,
        ["Snow Dagger"] = 255,
        ["SnowDagger"] = 255,
        ["Watergun"] = 250,
        ["Beachy"] = 160,
        ["Icecream"] = 160,
        ["Sands"] = 160,
        ["Treat"] = 155,
        ["Sweet"] = 150,
        ["Borealis"] = 145,
        ["Australis"] = 140,
        ["Bat"] = 120,
        ["Pearlshine"] = 90,
        ["Pearl"] = 85,
        ["Candy"] = 80,
        ["Heartblade"] = 65,
        ["Luger"] = 40,
        ["Red Luger"] = 37,
        ["RedLuger"] = 37,
        ["Phantom"] = 35,
        ["Spectre"] = 35,
        ["Candleflame"] = 33,
        ["Darkbringer"] = 33,
        ["Elderwood Blade"] = 33,
        ["ElderwoodBlade"] = 33,
        ["Elderwood Revolver"] = 33,
        ["ElderwoodRevolver"] = 33,
        ["Iceblaster"] = 33,
        ["Lightbringer"] = 33,
        ["Makeshift"] = 33,
        ["Sugar"] = 32,
        ["Ornament"] = 27,
        ["Green Luger"] = 23,
        ["GreenLuger"] = 23,
        ["Amerilaser"] = 22,
        ["Laser"] = 22,
        ["Hallowgun"] = 20,
        ["Nightblade"] = 20,
        ["Shark"] = 20,
        ["Icebeam"] = 18,
        ["Plasmabeam"] = 18,
        ["Swirly Gun"] = 18,
        ["SwirlyGun"] = 18,
        ["Battleaxe II"] = 17,
        ["BattleAxe II"] = 17,
        ["BattleaxeII"] = 17,
        ["Blaster"] = 17,
        ["Ginger Luger"] = 17,
        ["GingerLuger"] = 17,
        ["Pixel"] = 17,
        ["Gemstone"] = 15,
        ["Iceflake"] = 15,
        ["Old Glory"] = 15,
        ["OldGlory"] = 15,
        ["Plasmablade"] = 15,
        ["Slasher"] = 15,
        ["Vampire's Edge"] = 15,
        ["VampiresEdge"] = 15,
        ["Cookiecane"] = 13,
        ["Deathshard"] = 13,
        ["Eternalcane"] = 13,
        ["Gingerblade"] = 13,
        ["Jinglegun"] = 13,
        ["Lugercane"] = 13,
        ["Minty"] = 13,
        ["Nebula"] = 13,
        ["Virtual"] = 13,
        ["Battleaxe"] = 12,
        ["BattleAxe"] = 12,
        ["Gingermint"] = 12,
        ["Swirly Blade"] = 12,
        ["SwirlyBlade"] = 12,
        ["Chill"] = 10,
        ["Clockwork"] = 10,
        ["Fang"] = 10,
        ["Frostsaber"] = 10,
        ["Heat"] = 10,
        ["Spider"] = 10,
        ["Tides"] = 10,
        ["Bioblade"] = 8,
        ["Eternal III"] = 8,
        ["EternalIII"] = 8,
        ["Eternal IV"] = 8,
        ["EternalIV"] = 8,
        ["Hallow's Blade"] = 8,
        ["HallowsBlade"] = 8,
        ["Hallow's Edge"] = 8,
        ["HallowsEdge"] = 8,
        ["Handsaw"] = 8,
        ["Boneblade"] = 7,
        ["Eternal"] = 7,
        ["Eternal II"] = 7,
        ["EternalII"] = 7,
        ["Frostbite"] = 7,
        ["Ghostblade"] = 7,
        ["Ice Dragon"] = 7,
        ["IceDragon"] = 7,
        ["Ice Shard"] = 7,
        ["IceShard"] = 7,
        ["Prismatic"] = 7,
        ["Pumpking"] = 7,
        ["Saw"] = 7,
        ["Xmas"] = 7,
        ["Eggblade"] = 5,
        ["Flames"] = 5,
        ["Snowflake"] = 5,
        ["Winter's Edge"] = 5,
        ["WintersEdge"] = 5,
        ["Peppermint"] = 4,
        ["Cookieblade"] = 3,
        ["Blue Seer"] = 3,
        ["BlueSeer"] = 3,
        ["Purple Seer"] = 3,
        ["PurpleSeer"] = 3,
        ["Red Seer"] = 3,
        ["RedSeer"] = 3,
        ["Seer"] = 3,
        ["Orange Seer"] = 2,
        ["OrangeSeer"] = 2,
        ["Yellow Seer"] = 2,
        ["YellowSeer"] = 2,
    }

    local CHROMA_ITEM_VALUES = {
        -- Exact MM2 database ids for chromas whose display names omit "Chroma".
        ["TravelerGunChroma"] = 220000,
        ["TreeGun2023Chroma"] = 75000,
        ["TreeKnife2023Chroma"] = 50000,
        ["BaubleChroma"] = 34000,
        ["VampireGunChroma"] = 29000,
        ["ConstellationChroma"] = 27000,
        ["UFOKnifeChroma"] = 24000,
        ["SunsetGunChroma"] = 13250,
        ["RaygunChroma"] = 12000,
        ["SnowcannonChroma"] = 8500,
        ["SunsetKnifeChroma"] = 8250,
        ["BlizzardChroma"] = 8000,
        ["SnowDaggerChroma"] = 4250,
        ["SnowstormChroma"] = 4250,
        ["HeartWandChroma"] = 4250,
        ["WatergunChroma"] = 3400,
        ["TreatChroma"] = 2800,
        ["SweetChroma"] = 2300,
        ["IcecreamChroma"] = 2000,
        ["SandsChroma"] = 1800,
        ["BeachyChroma"] = 1750,
        ["BaubleKnifeChroma"] = 1800,
        ["DarkbringerChroma"] = 65,
        ["LightbringerChroma"] = 60,
        ["LugerChroma"] = 50,
        ["CandleflameChroma"] = 40,
        ["LaserChroma"] = 40,
        ["SwirlyGunChroma"] = 38,
        ["ElderwoodKnifeChroma"] = 37,
        ["DeathshardChroma"] = 35,
        ["Gingermint_KChroma"] = 32,
        ["FangChroma"] = 32,
        ["GemstoneChroma"] = 32,
        ["SharkChroma"] = 32,
        ["SlasherChroma"] = 32,
        ["HeatChroma"] = 28,
        ["SeerChroma"] = 28,
        ["GingerbladeChroma"] = 27,
        ["TidesChroma"] = 27,
        ["SawChroma"] = 23,
        ["BonebladeChroma"] = 22,
        ["Chroma Traveler's Gun"] = 220000,
        ["C. Traveler's Gun"] = 220000,
        ["ChromaTravelerGun"] = 220000,
        ["Chroma Evergun"] = 75000,
        ["ChromaEvergun"] = 75000,
        ["Chroma Evergreen"] = 50000,
        ["ChromaEvergreen"] = 50000,
        ["Chroma Bauble"] = 34000,
        ["ChromaBauble"] = 34000,
        ["Chroma Vampire's Gun"] = 29000,
        ["C. Vampire's Gun"] = 29000,
        ["ChromaVampiresGun"] = 29000,
        ["Chroma Constellation"] = 27000,
        ["C. Constellation"] = 27000,
        ["ChromaConstellation"] = 27000,
        ["Chroma Alienbeam"] = 24000,
        ["ChromaAlienbeam"] = 24000,
        ["Chroma Sunrise"] = 13250,
        ["ChromaSunrise"] = 13250,
        ["Chroma Raygun"] = 12000,
        ["ChromaRaygun"] = 12000,
        ["Chroma Snowcannon"] = 8500,
        ["ChromaSnowcannon"] = 8500,
        ["Chroma Sunset"] = 8250,
        ["ChromaSunset"] = 8250,
        ["Chroma Blizzard"] = 8000,
        ["ChromaBlizzard"] = 8000,
        ["Chroma Snow Dagger"] = 4250,
        ["ChromaSnowDagger"] = 4250,
        ["Chroma Snowstorm"] = 4250,
        ["ChromaSnowstorm"] = 4250,
        ["Chroma Heart Wand"] = 4250,
        ["ChromaHeartWand"] = 4250,
        ["Chroma Watergun"] = 3400,
        ["ChromaWatergun"] = 3400,
        ["Chroma Treat"] = 2800,
        ["ChromaTreat"] = 2800,
        ["Chroma Sweet"] = 2300,
        ["ChromaSweet"] = 2300,
        ["Chroma Icecream"] = 2000,
        ["ChromaIcecream"] = 2000,
        ["Chroma Sands"] = 1800,
        ["ChromaSands"] = 1800,
        ["Chroma Ornament"] = 1800,
        ["ChromaOrnament"] = 1800,
        ["Chroma Beachy"] = 1750,
        ["ChromaBeachy"] = 1750,
        ["Chroma Darkbringer"] = 65,
        ["ChromaDarkbringer"] = 65,
        ["Chroma Lightbringer"] = 60,
        ["ChromaLightbringer"] = 60,
        ["Chroma Luger"] = 50,
        ["ChromaLuger"] = 50,
        ["Chroma Candleflame"] = 40,
        ["ChromaCandleflame"] = 40,
        ["Chroma Laser"] = 40,
        ["ChromaLaser"] = 40,
        ["Chroma Swirly Gun"] = 38,
        ["ChromaSwirlyGun"] = 38,
        ["Chroma Elderwood Blade"] = 37,
        ["C. Elderwood Blade"] = 37,
        ["ChromaElderwoodBlade"] = 37,
        ["Chroma Deathshard"] = 35,
        ["ChromaDeathshard"] = 35,
        ["Chroma Cookiecane"] = 32,
        ["ChromaCookiecane"] = 32,
        ["Chroma Fang"] = 32,
        ["ChromaFang"] = 32,
        ["Chroma Gemstone"] = 32,
        ["ChromaGemstone"] = 32,
        ["Chroma Shark"] = 32,
        ["ChromaShark"] = 32,
        ["Chroma Slasher"] = 32,
        ["ChromaSlasher"] = 32,
        ["Chroma Heat"] = 28,
        ["ChromaHeat"] = 28,
        ["Chroma Seer"] = 28,
        ["ChromaSeer"] = 28,
        ["Chroma Gingerblade"] = 27,
        ["ChromaGingerblade"] = 27,
        ["Chroma Tides"] = 27,
        ["ChromaTides"] = 27,
        ["Chroma Saw"] = 23,
        ["ChromaSaw"] = 23,
        ["Chroma Boneblade"] = 22,
        ["ChromaBoneblade"] = 22,
    }

    local parent = safeParent()
    local oldGui = parent:FindFirstChild("CartiHubPlayerValuesGUI")
    if oldGui then
        oldGui:Destroy()
    end

    local function normalizeValueKey(value)
        return tostring(value or ""):lower():gsub("[^%w]", "")
    end

    local itemIdsByDisplayName = {}
    for _, itemType in ipairs({ "Weapons", "Item" }) do
        for itemId, data in pairs(sync[itemType] or {}) do
            if type(data) == "table" then
                local displayName = normalizeValueKey(data.ItemName or data.Name or itemId)
                itemIdsByDisplayName[displayName] = itemIdsByDisplayName[displayName] or {}
                itemIdsByDisplayName[displayName][tostring(itemId)] = true
            end
        end
    end

    local function isUniqueDisplayName(itemId, displayName)
        local ids = itemIdsByDisplayName[normalizeValueKey(displayName)]
        if not ids then
            return true
        end

        local count = 0
        for knownItemId in pairs(ids) do
            count += 1
            if knownItemId ~= tostring(itemId) then
                return false
            end
        end

        return count <= 1
    end

    local function readValue(valueTable, itemId, displayName)
        local direct = valueTable[itemId] or valueTable[normalizeValueKey(itemId)]
        if direct ~= nil then
            return tonumber(direct) or 0
        end

        if not isUniqueDisplayName(itemId, displayName) then
            return 0
        end

        return tonumber(valueTable[displayName] or valueTable[normalizeValueKey(displayName)]) or 0
    end

    local function isChromaValueItem(itemId, data)
        local chromaTexture = data and data.ChromaTexture
        local chromaStaticLayer = data and data.ChromaStaticLayer
        local hasChromaTexture = chromaTexture ~= nil
            and chromaTexture ~= false
            and tostring(chromaTexture) ~= ""
        local hasChromaStaticLayer = chromaStaticLayer ~= nil
            and chromaStaticLayer ~= false
            and tostring(chromaStaticLayer) ~= ""

        if type(data) == "table" and (
            data.Chroma == true
            or data.IsChroma == true
            or hasChromaTexture
            or hasChromaStaticLayer
        ) then
            return true
        end

        local itemText = normalizeValueKey(itemId)
        local nameText = normalizeValueKey(data and (data.ItemName or data.Name))
        return itemText:find("chroma", 1, true) ~= nil or nameText:find("chroma", 1, true) ~= nil
    end

    local function findValueItem(itemId, preferredType)
        local searchTypes = preferredType and { preferredType } or { "Weapons", "Item" }

        for _, itemType in ipairs(searchTypes) do
            local data = sync[itemType] and sync[itemType][itemId]
            if type(data) == "table" then
                local displayName = data.ItemName or data.Name or itemId
                local chroma = isChromaValueItem(itemId, data)
                local value = readValue(chroma and CHROMA_ITEM_VALUES or NORMAL_ITEM_VALUES, itemId, displayName)

                return {
                    ItemID = itemId,
                    ItemType = itemType,
                    Name = displayName,
                    Value = value,
                    Chroma = chroma,
                }
            end
        end

        return nil
    end

    local function sortAndLimit(items)
        table.sort(items, function(a, b)
            if a.Value == b.Value then
                return tostring(a.Name):lower() < tostring(b.Name):lower()
            end

            return a.Value > b.Value
        end)

        while #items > 3 do
            table.remove(items)
        end

        return items
    end

    local function getLocalPlayerValues()
        local found = {}
        local seen = {}

        local function collect(owned, itemType)
            for itemId, amount in pairs(owned or {}) do
                if (tonumber(amount) or 0) > 0 then
                    local entry = findValueItem(itemId, itemType)
                    local key = entry and (entry.ItemType .. ":" .. entry.ItemID)
                    if entry and not seen[key] then
                        seen[key] = true
                        entry.Amount = amount
                        table.insert(found, entry)
                    end
                end
            end
        end

        local displayed = Runtime.Inventory.profile()
        collect(displayed.Weapons and displayed.Weapons.Owned, "Weapons")
        return sortAndLimit(found)
    end

    local function getVisiblePlayerValues(player)
        if player == localPlayer then
            return getLocalPlayerValues()
        end

        local found = {}
        local seen = {}
        local attributes = {
            "EquippedKnife",
            "EquippedGun",
            "Knife",
            "Gun",
        }

        for _, attributeName in ipairs(attributes) do
            local itemId = player:GetAttribute(attributeName)
            if type(itemId) == "string" and itemId ~= "" then
                local entry = findValueItem(itemId)
                local key = entry and (entry.ItemType .. ":" .. entry.ItemID)
                if entry and not seen[key] then
                    seen[key] = true
                    table.insert(found, entry)
                end
            end
        end

        return sortAndLimit(found)
    end

    local gui = Runtime.screenGui()
    gui.Name = "CartiHubPlayerValuesGUI"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 100001
    gui.Enabled = false
    gui.Parent = parent

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 300, 0, 450)
    frame.Position = UDim2.new(0.5, -150, 0.5, -225)
    frame.BackgroundColor3 = Color3.fromRGB(9, 14, 31)
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = gui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(83, 220, 255)
    stroke.Thickness = 1
    stroke.Transparency = 0.15
    stroke.Parent = frame

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -130, 0, 40)
    title.Position = UDim2.new(0, 14, 0, 4)
    title.BackgroundTransparency = 1
    title.Text = "Players Values"
    title.TextColor3 = Color3.fromRGB(210, 245, 255)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 18
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = frame

    local refreshButton = Instance.new("TextButton")
    refreshButton.Size = UDim2.new(0, 72, 0, 28)
    refreshButton.Position = UDim2.new(1, -112, 0, 10)
    refreshButton.BackgroundColor3 = BUTTON_COLOR
    refreshButton.BorderSizePixel = 0
    refreshButton.Text = "REFRESH"
    refreshButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    refreshButton.Font = Enum.Font.GothamBold
    refreshButton.TextSize = 11
    refreshButton.Parent = frame
    Instance.new("UICorner", refreshButton).CornerRadius = UDim.new(0, 7)

    local closeButton = Instance.new("TextButton")
    closeButton.Size = UDim2.new(0, 28, 0, 28)
    closeButton.Position = UDim2.new(1, -36, 0, 10)
    closeButton.BackgroundTransparency = 1
    closeButton.Text = "X"
    closeButton.TextColor3 = Color3.fromRGB(255, 128, 207)
    closeButton.Font = Enum.Font.GothamBold
    closeButton.TextSize = 18
    closeButton.Parent = frame

    local scroll = Instance.new("ScrollingFrame")
    scroll.Size = UDim2.new(1, -16, 1, -56)
    scroll.Position = UDim2.new(0, 8, 0, 48)
    scroll.BackgroundTransparency = 1
    scroll.BorderSizePixel = 0
    scroll.ScrollBarThickness = 4
    scroll.ScrollBarImageColor3 = Color3.fromRGB(83, 220, 255)
    scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    scroll.Parent = frame

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 7)
    layout.Parent = scroll

    Runtime.connect(layout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
        scroll.CanvasSize = UDim2.new(0, 0, 0, Runtime.uiCanvasHeight(layout) + 8)
    end)

    local function formatValue(value)
        local text = tostring(math.floor(tonumber(value) or 0))
        local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
        return formatted
    end

    local function refreshValues()
        for _, child in ipairs(scroll:GetChildren()) do
            if child:IsA("GuiObject") then
                child:Destroy()
            end
        end

        local playerRows = {}
        for _, player in ipairs(Players:GetPlayers()) do
            local entries = getVisiblePlayerValues(player)
            table.insert(playerRows, {
                Player = player,
                Entries = entries,
                HighestValue = entries[1] and entries[1].Value or 0,
            })
        end

        table.sort(playerRows, function(a, b)
            if a.HighestValue == b.HighestValue then
                return a.Player.Name:lower() < b.Player.Name:lower()
            end
            return a.HighestValue > b.HighestValue
        end)

        for index, row in ipairs(playerRows) do
            local player = row.Player
            local entries = row.Entries
            local card = Instance.new("Frame")
            card.Size = UDim2.new(1, -4, 0, 88)
            card.BackgroundColor3 = Color3.fromRGB(16, 27, 55)
            card.BorderSizePixel = 0
            card.LayoutOrder = index
            card.Parent = scroll
            Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)

            local name = Instance.new("TextLabel")
            name.Size = UDim2.new(1, -20, 0, 22)
            name.Position = UDim2.new(0, 10, 0, 5)
            name.BackgroundTransparency = 1
            name.Text = player.Name
            name.TextColor3 = Color3.fromRGB(220, 240, 255)
            name.Font = Enum.Font.GothamBold
            name.TextSize = 14
            name.TextXAlignment = Enum.TextXAlignment.Left
            name.TextTruncate = Enum.TextTruncate.AtEnd
            name.Parent = card

            for line = 1, 3 do
                local entry = entries[line]
                local itemLabel = Instance.new("TextLabel")
                itemLabel.Size = UDim2.new(1, -20, 0, 17)
                itemLabel.Position = UDim2.new(0, 10, 0, 26 + ((line - 1) * 18))
                itemLabel.BackgroundTransparency = 1
                itemLabel.Font = Enum.Font.Gotham
                itemLabel.TextSize = 12
                itemLabel.TextXAlignment = Enum.TextXAlignment.Left
                itemLabel.TextTruncate = Enum.TextTruncate.AtEnd

                if entry then
                    local prefix = entry.Chroma and "[CHROMA] " or ""
                    local amount = entry.Amount and (" x" .. tostring(entry.Amount)) or ""
                    itemLabel.Text = prefix .. tostring(entry.Name) .. amount .. "  -  " .. formatValue(entry.Value)
                    itemLabel.TextColor3 = entry.Chroma
                        and Color3.fromRGB(255, 175, 255)
                        or Color3.fromRGB(240, 230, 255)
                elseif line == 1 then
                    itemLabel.Text = "No valued items found"
                    itemLabel.TextColor3 = Color3.fromRGB(190, 160, 220)
                else
                    itemLabel.Text = ""
                end

                itemLabel.Parent = card
            end
        end
    end

    Runtime.connect(closeButton.MouseButton1Click, function()
        gui.Enabled = false
    end)
    Runtime.connect(refreshButton.MouseButton1Click, refreshValues)

    local refreshQueued = false
    local function queuePlayerValuesRefresh(delaySeconds)
        if refreshQueued or not gui.Enabled then
            return
        end

        refreshQueued = true
        task.delay(delaySeconds or 0, function()
            refreshQueued = false
            if gui.Parent and gui.Enabled then
                refreshValues()
            end
        end)
    end

    Runtime.connect(Players.PlayerAdded, function()
        queuePlayerValuesRefresh(0.5)
    end)

    Runtime.connect(Players.PlayerRemoving, function()
        queuePlayerValuesRefresh()
    end)

    _G.CartiHubNormalItemValues = NORMAL_ITEM_VALUES
    _G.CartiHubChromaItemValues = CHROMA_ITEM_VALUES
    _G.CartiHubGetVisiblePlayerTopValue = function(player)
        local entries = getVisiblePlayerValues(player)
        return entries[1] and entries[1].Value or 0
    end
    _G.CartiHubOpenPlayerValuesGui = function()
        if not gui.Parent then
            return false
        end
        gui.Enabled = true
        refreshValues()
        return true
    end

    local oldBlockValueState = _G.CartiHubBlockValueState
    if oldBlockValueState then
        oldBlockValueState.Enabled = false
    end

    local blockValueState = {
        Enabled = false,
        Minimum = 0,
        Attempted = {},
    }
    _G.CartiHubBlockValueState = blockValueState

    local oldBlockValueGui = parent:FindFirstChild("CartiHubBlockValueGUI")
    if oldBlockValueGui then
        oldBlockValueGui:Destroy()
    end

    local blockValueGui = Runtime.screenGui()
    blockValueGui.Name = "CartiHubBlockValueGUI"
    blockValueGui.ResetOnSpawn = false
    blockValueGui.DisplayOrder = 100002
    blockValueGui.Enabled = false
    blockValueGui.Parent = parent

    local blockValueFrame = Instance.new("Frame")
    blockValueFrame.Size = UDim2.new(0, 280, 0, 164)
    blockValueFrame.Position = UDim2.new(0.5, -140, 0.5, -82)
    blockValueFrame.BackgroundColor3 = Color3.fromRGB(9, 14, 31)
    blockValueFrame.BorderSizePixel = 0
    blockValueFrame.Active = true
    blockValueFrame.Draggable = true
    blockValueFrame.Parent = blockValueGui
    Instance.new("UICorner", blockValueFrame).CornerRadius = UDim.new(0, 12)

    local blockValueStroke = Instance.new("UIStroke")
    blockValueStroke.Color = Color3.fromRGB(83, 220, 255)
    blockValueStroke.Thickness = 2
    blockValueStroke.Transparency = 0.15
    blockValueStroke.Parent = blockValueFrame

    local blockValueTitle = Instance.new("TextLabel")
    blockValueTitle.Size = UDim2.new(1, -46, 0, 36)
    blockValueTitle.Position = UDim2.new(0, 12, 0, 4)
    blockValueTitle.BackgroundTransparency = 1
    blockValueTitle.Text = "Block Value"
    blockValueTitle.TextColor3 = Color3.fromRGB(210, 245, 255)
    blockValueTitle.Font = Enum.Font.GothamBold
    blockValueTitle.TextSize = 17
    blockValueTitle.TextXAlignment = Enum.TextXAlignment.Left
    blockValueTitle.Parent = blockValueFrame

    local blockValueClose = Instance.new("TextButton")
    blockValueClose.Size = UDim2.new(0, 28, 0, 28)
    blockValueClose.Position = UDim2.new(1, -36, 0, 8)
    blockValueClose.BackgroundTransparency = 1
    blockValueClose.Text = "X"
    blockValueClose.TextColor3 = Color3.fromRGB(255, 128, 207)
    blockValueClose.Font = Enum.Font.GothamBold
    blockValueClose.TextSize = 18
    blockValueClose.Parent = blockValueFrame

    local minimumBox = Instance.new("TextBox")
    minimumBox.Size = UDim2.new(1, -24, 0, 36)
    minimumBox.Position = UDim2.new(0, 12, 0, 45)
    minimumBox.BackgroundColor3 = Color3.fromRGB(15, 25, 52)
    minimumBox.BorderSizePixel = 0
    minimumBox.PlaceholderText = "Minimum value"
    minimumBox.PlaceholderColor3 = Color3.fromRGB(120, 151, 191)
    minimumBox.Text = ""
    minimumBox.TextColor3 = Color3.fromRGB(220, 240, 255)
    minimumBox.Font = Enum.Font.Gotham
    minimumBox.TextSize = 14
    minimumBox.ClearTextOnFocus = false
    minimumBox.Parent = blockValueFrame
    Instance.new("UICorner", minimumBox).CornerRadius = UDim.new(0, 7)

    local blockValueToggle = Instance.new("TextButton")
    blockValueToggle.Size = UDim2.new(1, -24, 0, 36)
    blockValueToggle.Position = UDim2.new(0, 12, 0, 91)
    blockValueToggle.BackgroundColor3 = BUTTON_COLOR
    blockValueToggle.BorderSizePixel = 0
    blockValueToggle.Text = "BLOCK VALUE: OFF"
    blockValueToggle.TextColor3 = Color3.fromRGB(255, 255, 255)
    blockValueToggle.Font = Enum.Font.GothamBold
    blockValueToggle.TextSize = 13
    blockValueToggle.Parent = blockValueFrame
    Instance.new("UICorner", blockValueToggle).CornerRadius = UDim.new(0, 7)

    local blockValueStatus = Instance.new("TextLabel")
    blockValueStatus.Size = UDim2.new(1, -24, 0, 18)
    blockValueStatus.Position = UDim2.new(0, 12, 0, 132)
    blockValueStatus.BackgroundTransparency = 1
    blockValueStatus.Text = ""
    blockValueStatus.TextColor3 = Color3.fromRGB(210, 175, 245)
    blockValueStatus.Font = Enum.Font.Gotham
    blockValueStatus.TextSize = 11
    blockValueStatus.TextTruncate = Enum.TextTruncate.AtEnd
    blockValueStatus.Parent = blockValueFrame

    local function setBlockValueEnabled(enabled)
        blockValueState.Enabled = enabled == true
        blockValueToggle.Text = blockValueState.Enabled and "BLOCK VALUE: ON" or "BLOCK VALUE: OFF"
        blockValueToggle.BackgroundColor3 = blockValueState.Enabled and BUTTON_HOVER_COLOR or BUTTON_COLOR
        blockValueStatus.Text = blockValueState.Enabled
            and ("Blocking below " .. formatValue(blockValueState.Minimum))
            or ""
    end

    local function setMinimumValue()
        local cleaned = tostring(minimumBox.Text or ""):gsub(",", "")
        blockValueState.Minimum = math.max(0, math.floor(tonumber(cleaned) or 0))
        minimumBox.Text = blockValueState.Minimum > 0 and formatValue(blockValueState.Minimum) or ""
        if blockValueState.Enabled then
            blockValueStatus.Text = "Blocking below " .. formatValue(blockValueState.Minimum)
        end
    end

    Runtime.connect(minimumBox.FocusLost, setMinimumValue)
    Runtime.connect(blockValueToggle.MouseButton1Click, function()
        setMinimumValue()
        setBlockValueEnabled(not blockValueState.Enabled)
    end)
    Runtime.connect(blockValueClose.MouseButton1Click, function()
        blockValueGui.Enabled = false
    end)

    _G.CartiHubOpenBlockValueGui = function()
        if not blockValueGui.Parent then
            return false
        end
        blockValueGui.Enabled = true
        return true
    end

    task.spawn(function()
        while blockValueGui.Parent and _G.CartiHubBlockValueState == blockValueState do
            if blockValueState.Enabled then
                local blockUser = _G.CartiHubBlockUsername
                if type(blockUser) ~= "function" then
                    blockValueStatus.Text = "Block function unavailable"
                else
                    for _, player in ipairs(Players:GetPlayers()) do
                        if not blockValueState.Enabled or player == localPlayer then
                            continue
                        end

                        local topValue = _G.CartiHubGetVisiblePlayerTopValue(player)
                        if topValue < blockValueState.Minimum and not blockValueState.Attempted[player.UserId] then
                            blockValueState.Attempted[player.UserId] = true
                            blockValueStatus.Text = "Blocking " .. player.Name
                            blockUser(player.Name, function(success, detail)
                                if _G.CartiHubBlockValueState ~= blockValueState then
                                    return
                                end
                                blockValueStatus.Text = success and ("Blocked " .. player.Name) or tostring(detail or "Block failed")
                            end)
                            task.wait(0.5)
                        end
                    end
                end
                task.wait(3)
            else
                task.wait(0.25)
            end
        end
    end)

end)

task.defer(function()
    pcall(refreshMainInventoryNow)
end)

-- Roblox's contact list is protected CoreGui, so these companion controls are
-- positioned directly before its name column instead of modifying its rows.
task.spawn(function()
    local parent = safeParent()
    local oldGui = parent:FindFirstChild("CartiHubPlayerListBlockButtons")
    if oldGui then
        oldGui:Destroy()
    end

    local oldState = _G.CartiHubPlayerListBlockButtonState
    if oldState and oldState.Connections then
        for _, connection in ipairs(oldState.Connections) do
            pcall(function()
                connection:Disconnect()
            end)
        end
    end

    local state = {
        Connections = {},
        Blocking = {},
        Blocked = {},
        Enabled = _G.CartiHubPlayerListBlockButtonsEnabled == true,
    }
    _G.CartiHubPlayerListBlockButtonState = state

    local gui = Runtime.screenGui()
    gui.Name = "CartiHubPlayerListBlockButtons"
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 100000
    gui.Enabled = state.Enabled
    gui.Parent = parent

    local function getPlayerListOrder()
        local ordered = Players:GetPlayers()

        -- MM2's native player list orders its rows by prestige, then level.
        -- Those replicated attributes let the companion buttons follow new
        -- joins and removals without relying on a server-specific name list.
        table.sort(ordered, function(a, b)
            local aPrestige = tonumber(a:GetAttribute("Prestige")) or 0
            local bPrestige = tonumber(b:GetAttribute("Prestige")) or 0
            if aPrestige ~= bPrestige then
                return aPrestige > bPrestige
            end

            local aLevel = tonumber(a:GetAttribute("Level")) or 0
            local bLevel = tonumber(b:GetAttribute("Level")) or 0
            if aLevel ~= bLevel then
                return aLevel > bLevel
            end

            return a.Name:lower() < b.Name:lower()
        end)

        return ordered
    end

    local function refreshButtons()
        if not gui.Parent then
            return
        end

        for _, child in ipairs(gui:GetChildren()) do
            if child:IsA("GuiButton") then
                child:Destroy()
            end
        end

        if not state.Enabled then
            return
        end

        for index, player in ipairs(getPlayerListOrder()) do
            if player ~= localPlayer then
                local button = Instance.new("TextButton")
                button.Name = "Block_" .. tostring(player.UserId)
                button.AnchorPoint = Vector2.new(1, 0)
                button.Size = UDim2.fromOffset(70, 30)
                button.Position = UDim2.new(1, -284, 0, 22 + ((index - 1) * 42))
                button.BackgroundColor3 = state.Blocked[player.UserId]
                    and Color3.fromRGB(80, 80, 84)
                    or Color3.fromRGB(166, 48, 66)
                button.BackgroundTransparency = 0.08
                button.BorderSizePixel = 0
                button.Text = state.Blocked[player.UserId] and "DONE" or "BLOCK"
                button.TextColor3 = Color3.fromRGB(255, 255, 255)
                button.Font = Enum.Font.GothamBold
                button.TextSize = 8
                button.AutoButtonColor = not state.Blocked[player.UserId]
                button.Active = not state.Blocked[player.UserId]
                button.ZIndex = 100001
                button.Parent = gui
                Instance.new("UICorner", button).CornerRadius = UDim.new(0, 3)

                if not state.Blocked[player.UserId] then
                    Runtime.connect(button.MouseButton1Click, function()
                        if state.Blocking[player.UserId] then
                            return
                        end

                        local blockUser = _G.CartiHubBlockUsername
                        if type(blockUser) ~= "function" then
                            button.Text = "OFFLINE"
                            return
                        end

                        state.Blocking[player.UserId] = true
                        button.Text = "..."
                        button.Active = false

                        blockUser(player.Name, function(success, detail)
                            state.Blocking[player.UserId] = nil
                            if not button.Parent then
                                return
                            end

                            if success then
                                state.Blocked[player.UserId] = true
                                button.Text = "DONE"
                                button.BackgroundColor3 = Color3.fromRGB(80, 80, 84)
                            else
                                button.Text = tostring(detail or "FAILED")
                                task.delay(2, function()
                                    if button.Parent and not state.Blocked[player.UserId] then
                                        button.Text = "BLOCK"
                                        button.Active = true
                                    end
                                end)
                            end
                        end)
                    end)
                end
            end
        end
    end

    _G.CartiHubSetPlayerListBlockButtonsEnabled = function(enabled)
        state.Enabled = enabled == true
        _G.CartiHubPlayerListBlockButtonsEnabled = state.Enabled
        gui.Enabled = state.Enabled
        refreshButtons()
    end

    table.insert(state.Connections, Runtime.connect(Players.PlayerAdded, refreshButtons))
    table.insert(state.Connections, Runtime.connect(Players.PlayerRemoving, function()
        task.defer(refreshButtons)
    end))

    refreshButtons()
    while gui.Parent do
        refreshButtons()
        task.wait(0.75)
    end
end)

task.spawn(function()
    local assetId = "rbxassetid://86422603476263"
    local loadedOk, loadedObjects = pcall(function()
        return game:GetObjects(assetId)
    end)

    if not loadedOk or type(loadedObjects) ~= "table" or not loadedObjects[1] then
        warn("[Carti Hub] Nebula UI asset could not be loaded: " .. tostring(loadedObjects))
        return
    end

    local nebulaGui = loadedObjects[1]
    if not nebulaGui:IsA("ScreenGui") then
        nebulaGui = nebulaGui:FindFirstChildWhichIsA("ScreenGui", true)
    end

    if not nebulaGui then
        warn("[Carti Hub] Nebula UI asset did not contain a ScreenGui.")
        return
    end

    Runtime.ownGui(nebulaGui)
    nebulaGui.Name = "CartiHubNebula"
    nebulaGui.ResetOnSpawn = false
    nebulaGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    nebulaGui.Parent = safeParent()
    _G.CartiHubNebulaGui = nebulaGui

    local uiFolder = nebulaGui:FindFirstChild("UI")
    local panel = uiFolder and uiFolder:FindFirstChild("Panel")
    local panelFrame = panel and panel:FindFirstChild("MainFrame")
    local panelContainer = panelFrame and panelFrame:FindFirstChild("Container")
    local ribbon = panelFrame and panelFrame:FindFirstChild("Ribbon")
    local topbar = panelFrame and panelFrame:FindFirstChild("Topbar")

    if not panelFrame or not panelContainer or not ribbon or not topbar then
        nebulaGui:Destroy()
        _G.CartiHubNebulaGui = nil
        warn("[Carti Hub] Nebula UI asset is missing the PC panel layout.")
        return
    end

    for _, surfaceName in ipairs({ "Menu", "Command Bar", "Popups" }) do
        local surface = uiFolder:FindFirstChild(surfaceName)
        if surface and surface:IsA("GuiObject") then
            surface.Visible = false
        end
    end

    local panelPopups = panel:FindFirstChild("Popups")
    if panelPopups and panelPopups:IsA("GuiObject") then
        panelPopups.Visible = false
    end

    panel.Visible = true
    panelFrame.Visible = true
    panel.Size = UDim2.new(0, 360, 0, 535)
    panel.Position = UDim2.new(0.5, 0, 0.5, 0)

    local sizeConstraint = panel:FindFirstChildOfClass("UISizeConstraint")
    if sizeConstraint then
        sizeConstraint.MinSize = Vector2.new(360, 535)
        sizeConstraint.MaxSize = Vector2.new(360, 535)
    end

    local aspectConstraint = panel:FindFirstChildOfClass("UIAspectRatioConstraint")
    if aspectConstraint then
        aspectConstraint:Destroy()
    end

    panelFrame.Active = true
    panelContainer.ClipsDescendants = true

    for _, child in ipairs(panelContainer:GetChildren()) do
        if child:IsA("GuiObject") then
            child:Destroy()
        end
    end

    for _, ribbonSideName in ipairs({ "Left", "Right" }) do
        local ribbonSide = ribbon:FindFirstChild(ribbonSideName)
        if ribbonSide then
            for _, child in ipairs(ribbonSide:GetChildren()) do
                if child:IsA("GuiObject") or child:IsA("UIListLayout") or child:IsA("UIPadding") then
                    child:Destroy()
                end
            end
        end
    end

    for _, topbarSideName in ipairs({ "Left", "Middle", "Right" }) do
        local topbarSide = topbar:FindFirstChild(topbarSideName)
        if topbarSide then
            for _, child in ipairs(topbarSide:GetChildren()) do
                if child:IsA("GuiObject") then
                    child:Destroy()
                end
            end
        end
    end

    local dragHandle = Instance.new("TextButton")
    dragHandle.Name = "CartiHubDragHandle"
    dragHandle.Size = UDim2.fromScale(1, 1)
    dragHandle.BackgroundTransparency = 1
    dragHandle.BorderSizePixel = 0
    dragHandle.Text = ""
    dragHandle.AutoButtonColor = false
    dragHandle.Active = true
    dragHandle.ZIndex = 20
    dragHandle.Parent = topbar

    local topbarLeft = topbar:FindFirstChild("Left")
    if topbarLeft then
        local logo = Instance.new("ImageLabel")
        logo.Name = "CartiHubLogo"
        logo.Size = UDim2.new(0, 18, 0, 18)
        logo.Position = UDim2.new(0, 9, 0.5, -9)
        logo.BackgroundTransparency = 1
        logo.Image = "rbxassetid://85529926460930"
        logo.ScaleType = Enum.ScaleType.Fit
        logo.ZIndex = 22
        logo.Parent = topbarLeft
    end

    TabContainer.Parent = ribbon
    TabContainer.BackgroundTransparency = 1
    TabContainer.Size = UDim2.new(1, -18, 1, -8)
    TabContainer.Position = UDim2.new(0, 9, 0, 4)
    TabContainer.ZIndex = 20

    TabLayout.FillDirection = Enum.FillDirection.Horizontal
    TabLayout.FillDirectionMaxCells = 7
    TabLayout.CellSize = UDim2.new(1 / 7, -4, 1, 0)
    TabLayout.CellPadding = UDim2.new(0, 4, 0, 0)

    for _, tab in ipairs({ SpawnerTabBtn, TradeTabBtn, UpgradingTabBtn, BlockTabBtn, SettingsTabBtn, KeybindsTabBtn, Runtime.NPCTab }) do
        tab.Size = UDim2.new(0, 0, 0, 0)
        tab.BackgroundTransparency = 1
        tab.TextXAlignment = Enum.TextXAlignment.Center
        tab.TextColor3 = Color3.fromRGB(192, 181, 208)
        tab.TextSize = 8

        local padding = tab:FindFirstChildOfClass("UIPadding")
        if padding then
            padding:Destroy()
        end

        local accent = tab:FindFirstChild("NebulaActiveAccent")
        if accent then
            accent.Visible = false
        end
    end

    for _, page in ipairs({ SpawnerFrame, TradeFrame, UpgradingFrame, BlockFrame, SettingsFrame, KeybindsFrame, Runtime.NPCFrame }) do
        page.Parent = panelContainer
        page.Size = UDim2.new(1, -24, 1, -20)
        page.Position = UDim2.new(0, 12, 0, 10)
        page.ZIndex = 12
        page.ScrollBarThickness = 3
    end

    local middle = topbar:FindFirstChild("Middle")
    if middle then
        Title.Parent = middle
        Title.Size = UDim2.new(1, 0, 1, 0)
        Title.Position = UDim2.fromScale(0, 0)
        Title.Text = "t.me/cartiscripts"
        Title.TextSize = 11
        Title.TextXAlignment = Enum.TextXAlignment.Center
        Title.ZIndex = 22
    end

    local right = topbar:FindFirstChild("Right")
    if right then
        CloseBtn.Parent = right
        CloseBtn.Size = UDim2.new(0, 28, 1, 0)
        CloseBtn.Position = UDim2.new(1, -30, 0, 0)
        CloseBtn.TextSize = 14
        CloseBtn.ZIndex = 22
    end

    local bottom = panelFrame:FindFirstChild("Bottom")
    local bottomLeft = bottom and bottom:FindFirstChild("Left")
    if bottomLeft then
        for _, label in ipairs(bottomLeft:GetDescendants()) do
            if label:IsA("TextLabel") then
                label.Text = label.Text == "" and localPlayer.Name or label.Text
            end
        end
    end

    Runtime.connect(CloseBtn.MouseButton1Click, function()
        Runtime.shutdown()
    end)

    MainFrame.Visible = false
    if Runtime.ResponsiveUI and Runtime.ResponsiveUI.Active then
        local ui = Runtime.ResponsiveUI
        local sizeButton = ui:AddSizeButton(topbar)
        for _, part in ipairs({topbar, ribbon, panelContainer}) do
            local constraint = part:FindFirstChildOfClass('UISizeConstraint')
            if constraint then constraint:Destroy() end
        end
        ui:Register(panel, {Base = Vector2.new(360, 535), DragHandle = dragHandle, Layout = function(compact)
            local barHeight = compact and 44 or 38
            topbar.AnchorPoint, topbar.Position, topbar.Size = Vector2.zero, UDim2.new(), UDim2.new(1, 0, 0, barHeight)
            ribbon.AnchorPoint, ribbon.Position, ribbon.Size = Vector2.zero, UDim2.fromOffset(0, barHeight), UDim2.new(1, 0, 0, compact and 46 or 38)
            panelContainer.AnchorPoint, panelContainer.Position = Vector2.zero, UDim2.fromOffset(0, barHeight + (compact and 46 or 38))
            panelContainer.Size = UDim2.new(1, 0, 1, -(barHeight + (compact and 46 or 38) + 30))
            TabContainer.Position, TabContainer.Size = UDim2.fromOffset(9, compact and 2 or 4), UDim2.new(1, -18, 1, compact and -4 or -8)
            sizeButton.Visible = compact
            CloseBtn.Size, CloseBtn.Position = UDim2.new(0, compact and 44 or 28, 1, 0), UDim2.new(1, compact and -46 or -30, 0, 0)
            Title.TextSize = compact and 13 or 11
            Title.TextTruncate = Enum.TextTruncate.AtEnd
            ui:LayoutTabs(compact, false)
        end})
    end
end)
