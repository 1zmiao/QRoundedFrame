#include <windows.h>

#include <string>
#include <vector>

static std::wstring quoteArg(const std::wstring &value) {
    std::wstring out = L"\"";
    for (wchar_t ch : value) {
        if (ch == L'"')
            out += L"\\\"";
        else
            out += ch;
    }
    out += L"\"";
    return out;
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    wchar_t modulePath[MAX_PATH] = {};
    if (!GetModuleFileNameW(nullptr, modulePath, MAX_PATH))
        return 1;

    std::wstring base(modulePath);
    const std::wstring::size_type slash = base.find_last_of(L"\\/");
    if (slash != std::wstring::npos)
        base.resize(slash);

    const std::wstring runtimeDir = base + L"\\runtime";
    const std::wstring appPath = runtimeDir + L"\\QRoundedFrame.exe";

    DWORD attrs = GetFileAttributesW(appPath.c_str());
    if (attrs == INVALID_FILE_ATTRIBUTES || (attrs & FILE_ATTRIBUTE_DIRECTORY)) {
        MessageBoxW(nullptr, L"runtime\\QRoundedFrame.exe not found.", L"QRoundedFrame", MB_ICONERROR | MB_OK);
        return 1;
    }

    std::wstring commandLine = quoteArg(appPath);
    int argc = 0;
    LPWSTR *argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (argv) {
        for (int i = 1; i < argc; ++i) {
            commandLine += L" ";
            commandLine += quoteArg(argv[i]);
        }
        LocalFree(argv);
    }

    const DWORD envSize = GetEnvironmentVariableW(L"PATH", nullptr, 0);
    std::wstring pathValue;
    if (envSize > 0) {
        pathValue.resize(envSize);
        GetEnvironmentVariableW(L"PATH", pathValue.data(), envSize);
        while (!pathValue.empty() && pathValue.back() == L'\0')
            pathValue.pop_back();
    }
    const std::wstring nextPath = runtimeDir + L";" + pathValue;
    SetEnvironmentVariableW(L"PATH", nextPath.c_str());
    SetEnvironmentVariableW(L"QROUNDEDFRAME_ROOT", runtimeDir.c_str());
    SetEnvironmentVariableW(L"QROUNDEDFRAME_USER_DATA_ROOT", base.c_str());

    STARTUPINFOW si = {};
    si.cb = sizeof(si);
    PROCESS_INFORMATION pi = {};
    std::vector<wchar_t> mutableCommand(commandLine.begin(), commandLine.end());
    mutableCommand.push_back(L'\0');

    BOOL ok = CreateProcessW(
        appPath.c_str(),
        mutableCommand.data(),
        nullptr,
        nullptr,
        FALSE,
        0,
        nullptr,
        runtimeDir.c_str(),
        &si,
        &pi);
    if (!ok) {
        MessageBoxW(nullptr, L"Failed to start runtime\\QRoundedFrame.exe.", L"QRoundedFrame", MB_ICONERROR | MB_OK);
        return 1;
    }
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return 0;
}
