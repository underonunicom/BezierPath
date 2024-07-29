--!optimize 2
--!native
--!strict

local EPSILON = 100

type Section = {
	Positions : {Vector3},
	Length : number,
	Type : number,
	TRanges : {number},
	AccumulatedDistance : number
}

type Methods = {
	CalculateUniformPosition: (self : Path,T : number) -> Vector3,
	CalculateUniformCFrame: (self : Path,T : number) -> CFrame,
	CalculateDerivative: (self : Path,T : number) -> Vector3,
	GetPathLength: (self : Path) -> number,
	CalculateClosestPoint: (self : Path,Position : Vector3,Iterations : number?) -> (CFrame,number)
}

export type Path = {
	Sections : {Section},
	PathLength : number,
} & Methods

type Module = {
	new: (Waypoints : {Vector3},CurveSize : number) -> Path,
}

local BezierPath : Module = {} :: Module
local Methods : Methods = {} :: Methods

local function Bezier(p0: Vector3, p1: Vector3, p2: Vector3, t: number) : Vector3 
	return p1 + (1-t)^2*(p0 - p1)+t^2*(p2 - p1)
end

local function BezierDerivative(p0: Vector3, p1: Vector3, p2: Vector3, t: number) : Vector3
	return 2*(1 - t)*(p1-p0) + 2*t*(p2-p1)
end

local function Lerp(p0: Vector3, p1: Vector3, t: number) : Vector3
	return p0 + t*(p1 - p0)
end

local function CalculateSectionPosition(Section : Section,T : number) : Vector3
	local Positions = Section.Positions
	
	if Section.Type == 1 then
		return Lerp(Positions[1],Positions[2],T)
	else
		return Bezier(Positions[1],Positions[2],Positions[3],T)
	end
end

local function CalculateSectionDerivative(Section : Section,T : number) : Vector3
	local Positions = Section.Positions
	
	return BezierDerivative(Positions[1],Positions[2],Positions[3],T)
end

local function CalculateSectionCFrame(Section : Section,T : number) : CFrame
	local Position = CalculateSectionPosition(Section,T)
	local Derivative = CalculateSectionDerivative(Section,T)
	
	return CFrame.new(Position,Position + Derivative)
end

local function SetupWaypoints(InputtedWaypoints : {Vector3},CurveSize : number) : {Vector3}
	local Waypoints = {}
	
	table.insert(Waypoints,InputtedWaypoints[1]) 
	 
	for i = 2,#InputtedWaypoints - 1 do
		local Position = InputtedWaypoints[i]
		local PreviousPosition = InputtedWaypoints[i - 1]
		local NextPosition = InputtedWaypoints[i + 1]
		
		local PreviousPosition = Position - (Position - PreviousPosition).Unit * CurveSize
		local NextPosition =  Position - (Position - NextPosition).Unit * CurveSize
		
		table.insert(Waypoints,PreviousPosition)
		table.insert(Waypoints,Position)
		table.insert(Waypoints,NextPosition)
	end
	
	table.insert(Waypoints,InputtedWaypoints[#InputtedWaypoints])
	
	return Waypoints
end

local function CalculateSectionLength(Section : Section) : number
	local Length = 0
	
	for T = 0,1,1/EPSILON do
		local Position1 = CalculateSectionPosition(Section,T)
		local Position2 = CalculateSectionPosition(Section,T + 1/EPSILON)
		
		Length += (Position1 - Position2).Magnitude
	end
	
	return Length
end

local function CalculatePathLength(Sections : {Section})
	local TotalLength = 0
	
	for _,Section in Sections do
		TotalLength += Section.Length
	end
	
	return TotalLength
end

local function CreateSections(BezierWaypoints : {Vector3}) : {Section}
	local Sections = {}
	
	local Index = 2
	local Step = 1
	
	while Index <= #BezierWaypoints do
		local SectionPositions = {}
		
		local PreviousPosition = BezierWaypoints[Index - 1]
		local Position = BezierWaypoints[Index]
		local NextPosition = BezierWaypoints[Index + 1]
		
		if Step == 1 then
			table.insert(SectionPositions,PreviousPosition)
			table.insert(SectionPositions,Position)
			table.insert(SectionPositions,Position)
		else
			table.insert(SectionPositions,PreviousPosition)
			table.insert(SectionPositions,Position)
			table.insert(SectionPositions,NextPosition)
		end
		
		local newSection = {
			AccumulatedDistance = 0,
			Positions = SectionPositions,
			Type = Step,
			Length = 0,
			TRanges = {},
			
		}
		
		newSection.Length = CalculateSectionLength(newSection)
		
		Index += Step
		Step = Step == 1 and 2 or 1
		
		table.insert(Sections,newSection)
	end
	
	return Sections
end

local function SetupSectionsT(PathLength : number,Sections : {Section})
	local AccumulatedT = 0
	
	for i = 1,#Sections do
		local Section = Sections[i]
		local PortionOfPath = Section.Length / PathLength
		Section.TRanges = {AccumulatedT,AccumulatedT + PortionOfPath}
		
		AccumulatedT += PortionOfPath
	end
end

local function SetupSectionsAccumulatedDistance(Sections : {Section})
	local AccumulatedDistance = 0
	
	for SectionIndex = 1,#Sections do
	    local Section = Sections[SectionIndex]		
		 
		Section.AccumulatedDistance = AccumulatedDistance
		AccumulatedDistance += Section.Length
	end
end

local function MapT(Section : Section,PathLength : number,T : number) : number
	if T >= 1 then return 1 end
	
	local InputtedDistance = T * PathLength
	local AccumulatedDistance = Section.AccumulatedDistance
		
	return (InputtedDistance - AccumulatedDistance) / Section.Length
end

local function GetSectionFromT(Sections : {Section},T : number) : Section
	for _,Section in Sections do
		if Section.TRanges[1] <= T and Section.TRanges[2] > T then
			return Section
		end
	end
	
	return Sections[#Sections]
end

local function LoadMethods(Object : {})
	for FunctionName,Function in Methods do
		if FunctionName == "new" then continue end
		
		Object[FunctionName] = Function
	end
end

function BezierPath.new(Waypoints : {Vector3},CurveSize : number) : Path
	local BezierWaypoints = SetupWaypoints(Waypoints,CurveSize)
	
	local Sections = CreateSections(BezierWaypoints)
	local PathLength = CalculatePathLength(Sections)
	SetupSectionsT(PathLength,Sections)
	SetupSectionsAccumulatedDistance(Sections)
		
	local newPath : Path = {
		Sections = Sections,
		PathLength = PathLength
	} :: Path
	
	LoadMethods(newPath)
	
	return newPath
end
  
function Methods:GetPathLength() : number
	return self.PathLength
end

function Methods:CalculateUniformPosition(T : number) : Vector3
	local Section = GetSectionFromT(self.Sections,T)
	local MappedT = MapT(Section,self.PathLength,T)
	
	return CalculateSectionPosition(Section,MappedT)
end

function Methods:CalculateUniformCFrame(T : number) : CFrame
	local Section = GetSectionFromT(self.Sections,T)
	local MappedT = MapT(Section,self.PathLength,T)

	return CalculateSectionCFrame(Section,MappedT)
end

function Methods:CalculateDerivative(T : number) : Vector3
	local Section = GetSectionFromT(self.Sections,T)
	local MappedT = MapT(Section,self.PathLength,T)
	
	return CalculateSectionDerivative(Section,MappedT)
end

function Methods:CalculateClosestPoint(Position: Vector3, Iterations: number?) : (CFrame, number)
	local Start = 0
	local End = 1
	local MaxIterations = Iterations or 20
	local Precision = 1e-6 -- Adjust precision as needed
	local ClosestT = 0

	for i = 1, MaxIterations do
		local Middle1 = Start + (End - Start) / 3
		local Middle2 = End - (End - Start) / 3

		local Position1 = self:CalculateUniformPosition(Start)
		local Position2 = self:CalculateUniformPosition(Middle1)
		local Position3 = self:CalculateUniformPosition(Middle2)
		local Position4 = self:CalculateUniformPosition(End)

		local Distance1 = (Position1 - Position).Magnitude
		local Distance2 = (Position2 - Position).Magnitude
		local Distance3 = (Position3 - Position).Magnitude
		local Distance4 = (Position4 - Position).Magnitude

		if Distance1 < Distance2 and Distance1 < Distance3 and Distance1 < Distance4 then
			ClosestT = Start
			End = Middle2
		elseif Distance4 < Distance1 and Distance4 < Distance2 and Distance4 < Distance3 then
			ClosestT = End
			Start = Middle1
		elseif Distance2 < Distance3 then
			ClosestT = Middle1
			End = Middle2
		else
			ClosestT = Middle2
			Start = Middle1
		end

		if (End - Start) < Precision then
			break
		end
	end

	return self:CalculateUniformCFrame(ClosestT), ClosestT
end


return BezierPath 
