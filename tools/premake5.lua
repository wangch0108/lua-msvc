local premakeDir = path.getabsolute(".")
print(premakeDir)
local projectDir = path.getabsolute("../")
os.chdir(projectDir)

workspace "LuaSrc"
    startproject "lua"
    architecture "x64"
    configurations
    {
        "Debug",
        "Release",
    }

outputdir = "%{cfg.buildcfg}-%{cfg.system}-%{cfg.architecture}"

project "lualib"
    kind "StaticLib"
    language "C"
    staticruntime "on"

    targetdir ("bin/" .. outputdir .. "/%{prj.name}")
    objdir ("bin-int/" .. outputdir .. "/%{prj.name}")

    files
	{
        "src/**.h",
        "src/**.c"
    }

    excludes
    {
        "src/lua.c",
        "src/onelua.c", -- gcc build
    }

    includedirs
    {
        "src"
    }

    filter "configurations:Debug"
        runtime "Debug"
        symbols "on"

    filter "configurations:Release"
        runtime "Release"
        optimize "on"

project "lua"
    kind "ConsoleApp"
    language "C"
    staticruntime "on"

    targetdir ("bin/" .. outputdir .. "/%{prj.name}")
    objdir ("bin-int/" .. outputdir .. "/%{prj.name}")

    files
    {
        "src/lua.c",
    }

    links
    {
        "lualib"
    }

    filter "configurations:Debug"
        runtime "Debug"
        symbols "on"

    filter "configurations:Release"
        runtime "Release"
        optimize "on"