-- vtypes
ffi.cdef[[
    static const int MAX_PATH = 260;
    typedef uint32_t DWORD;
    typedef char    CHAR; typedef wchar_t WCHAR;
    typedef uint32_t DEVICE_TYPE;
    typedef uint32_t ULONG;
    typedef void*    HANDLE;
    typedef void*    HLOCAL;
    typedef void*    LPVOID;
    typedef uint32_t BOOL;

    typedef struct _OVERLAPPED {
        unsigned long* Internal;
        unsigned long* InternalHigh;
        union {
            struct {
                unsigned long Offset;
                unsigned long OffsetHigh;
            } DUMMYSTRUCTNAME;
            void* Pointer;
        } DUMMYUNIONNAME;
        void*    hEvent;
    } OVERLAPPED, *LPOVERLAPPED;
]]

local DWORD = ffi.typeof("DWORD")
local PCHAR, PWCHAR = ffi.typeof("CHAR*"), ffi.typeof("WCHAR*")
local VLA_CHAR, VLA_WCHAR  = ffi.typeof("CHAR[?]"), ffi.typeof("WCHAR[?]")

-- funcs
ffi.cdef[[
    DWORD __stdcall GetLastError();
    DWORD __stdcall GetCurrentDirectoryA( DWORD nBufferLength, CHAR* lpBuffer );
    DWORD __stdcall GetCurrentDirectoryW( DWORD nBufferLength, CHAR* lpBuffer );

    BOOL __stdcall CreateDirectoryA( const CHAR* src, void* lpSecurityAttributes );
    BOOL __stdcall CreateDirectoryW( const CHAR* src, void* lpSecurityAttributes );
    BOOL __stdcall WriteFile( HANDLE hFile, CHAR* lpBuffer, DWORD nNumberOfBytesToWrite, DWORD* lpNumberOfBytesWritten, LPOVERLAPPED lpOverlapped );

    HANDLE __stdcall CreateFileA( const CHAR* lpFileName, 
        DWORD dwDesiredAccess, 
        DWORD dwShareMode, 
        void* lpSecurityAttributes, 
        DWORD dwCreationDisposition, 
        DWORD dwFlagsAndAttributes, 
    HANDLE hTemplateFile );
]]

local NULL = ffi.cast("void*", 0)
local NULLSTR = ffi.cast("CHAR*", NULL)
local NEXT = [[\]]
