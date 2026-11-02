#pragma once
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <iphlpapi.h>
#include <string>
#include <vector>
#include <memory>
#include <shellapi.h>
#include <shlobj.h>
#include <wlanapi.h>
#include <mmsystem.h>
#include <cstring>

namespace az {
inline std::string Utf8(const std::wstring& text) {
  if(text.empty()) return {};
  int count=WideCharToMultiByte(CP_UTF8,0,text.data(),static_cast<int>(text.size()),nullptr,0,nullptr,nullptr);
  std::string out(count,0); WideCharToMultiByte(CP_UTF8,0,text.data(),static_cast<int>(text.size()),out.data(),count,nullptr,nullptr); return out;
}
inline std::wstring Wide(const std::string& text) {
  if(text.empty()) return {};
  int n=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,text.data(),static_cast<int>(text.size()),nullptr,0);
  std::wstring out(n,0); if(n) MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,text.data(),static_cast<int>(text.size()),out.data(),n); return out;
}
inline uint64_t TimeValue(FILETIME t) { return (static_cast<uint64_t>(t.dwHighDateTime)<<32)|t.dwLowDateTime; }
inline flutter::EncodableList Snapshot() {
  using V=flutter::EncodableValue; flutter::EncodableList rows;
  auto add=[&](const std::string& label,const std::string& value,double ratio=-1.0,const std::string& status="available") {
    flutter::EncodableMap row{{V("label"),V(label)},{V("value"),V(value)},{V("status"),V(status)}};
    if(ratio>=0) { row[V("ratio")]=V(ratio); }
    rows.emplace_back(row);
  };
  MEMORYSTATUSEX memory{}; memory.dwLength=sizeof(memory);
  if(GlobalMemoryStatusEx(&memory)) {
    add("System RAM used",std::to_string((memory.ullTotalPhys-memory.ullAvailPhys)/1048576)+" / "+std::to_string(memory.ullTotalPhys/1048576)+" MiB",memory.dwMemoryLoad/100.0);
    add("Available system RAM",std::to_string(memory.ullAvailPhys/1048576)+" MiB");
  }
  FILETIME idle{},kernel{},user{}; static uint64_t oldIdle=0,oldTotal=0;
  if(GetSystemTimes(&idle,&kernel,&user)) { uint64_t currentIdle=TimeValue(idle),currentTotal=TimeValue(kernel)+TimeValue(user); if(oldTotal && currentTotal>oldTotal) { double load=1.0-static_cast<double>(currentIdle-oldIdle)/(currentTotal-oldTotal); add("System CPU load",std::to_string(load*100).substr(0,5)+"%",load); } else add("System CPU load","Collecting initial sample",-1,"temporarilyUnavailable"); oldIdle=currentIdle; oldTotal=currentTotal; }
  wchar_t cpu[256]{}; DWORD size=sizeof(cpu);
  if(RegGetValueW(HKEY_LOCAL_MACHINE,L"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0",L"ProcessorNameString",RRF_RT_REG_SZ,nullptr,cpu,&size)==ERROR_SUCCESS) add("Processor",Utf8(cpu));
  DWORD mhz=0; size=sizeof(mhz);
  if(RegGetValueW(HKEY_LOCAL_MACHINE,L"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0",L"~MHz",RRF_RT_REG_DWORD,nullptr,&mhz,&size)==ERROR_SUCCESS) add("Reported processor clock",std::to_string(mhz)+" MHz (registry nominal value)");
  for(const auto* field : {L"SystemManufacturer",L"SystemProductName"}) {
    wchar_t value[256]{}; size=sizeof(value);
    if(RegGetValueW(HKEY_LOCAL_MACHINE,L"HARDWARE\\DESCRIPTION\\System\\BIOS",field,RRF_RT_REG_SZ,nullptr,value,&size)==ERROR_SUCCESS) add(Utf8(field),Utf8(value));
  }
  SYSTEM_INFO system{}; GetNativeSystemInfo(&system); add("Logical processors",std::to_string(system.dwNumberOfProcessors)); add("Architecture",system.wProcessorArchitecture==PROCESSOR_ARCHITECTURE_AMD64?"x64":"Other");
  SYSTEM_POWER_STATUS power{};
  if(GetSystemPowerStatus(&power) && power.BatteryFlag!=128 && power.BatteryLifePercent!=255) { add("Battery charge",std::to_string(power.BatteryLifePercent)+"%",power.BatteryLifePercent/100.0); add("Power source",power.ACLineStatus==1?"AC":"Battery"); } else add("Battery","No battery information",-1,"unsupported");
  add("Battery temperature / wear","Unsupported by this adapter",-1,"unsupported");
  wchar_t drives[512]{}; DWORD count=GetLogicalDriveStringsW(512,drives);
  if(count>0 && count<512) for(wchar_t* drive=drives;*drive;drive+=wcslen(drive)+1) {
    UINT type=GetDriveTypeW(drive); if(type!=DRIVE_FIXED && type!=DRIVE_REMOVABLE) continue;
    ULARGE_INTEGER available{},total{},free{}; if(GetDiskFreeSpaceExW(drive,&available,&total,&free) && total.QuadPart) {
      add(Utf8(drive)+" volume used",std::to_string((total.QuadPart-free.QuadPart)/1073741824)+" / "+std::to_string(total.QuadPart/1073741824)+" GiB",1.0-static_cast<double>(free.QuadPart)/total.QuadPart);
      add(Utf8(drive)+" available",std::to_string(available.QuadPart/1048576)+" MiB");
      wchar_t filesystem[64]{};
      if(GetVolumeInformationW(drive,nullptr,0,nullptr,nullptr,nullptr,filesystem,64)) add(Utf8(drive)+" filesystem",Utf8(filesystem));
    }
  }
  ULONG length=16384; std::vector<unsigned char> buffer(length); auto adapters=reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
  ULONG code=GetAdaptersAddresses(AF_UNSPEC,GAA_FLAG_SKIP_ANYCAST|GAA_FLAG_SKIP_MULTICAST,nullptr,adapters,&length);
  if(code==ERROR_BUFFER_OVERFLOW) { buffer.resize(length); adapters=reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data()); code=GetAdaptersAddresses(AF_UNSPEC,GAA_FLAG_SKIP_ANYCAST|GAA_FLAG_SKIP_MULTICAST,nullptr,adapters,&length); }
  if(code==NO_ERROR) for(auto adapter=adapters;adapter;adapter=adapter->Next) if(adapter->OperStatus==IfOperStatusUp) {
    add("Network adapter",Utf8(adapter->FriendlyName));
    for(auto unicast=adapter->FirstUnicastAddress;unicast;unicast=unicast->Next) {
      char address[INET6_ADDRSTRLEN]{}; auto socket=unicast->Address.lpSockaddr;
      const void* data=socket->sa_family==AF_INET?static_cast<const void*>(&reinterpret_cast<sockaddr_in*>(socket)->sin_addr):socket->sa_family==AF_INET6?static_cast<const void*>(&reinterpret_cast<sockaddr_in6*>(socket)->sin6_addr):nullptr;
      if(data && InetNtopA(socket->sa_family,const_cast<void*>(data),address,sizeof(address))) add("Local IP",address);
    }
  }
  HANDLE wlan=nullptr; DWORD version=0;
  DWORD opened=WlanOpenHandle(2,nullptr,&version,&wlan);
  bool wifiFound=false;
  if(opened==ERROR_SUCCESS) {
    PWLAN_INTERFACE_INFO_LIST interfaces=nullptr;
    if(WlanEnumInterfaces(wlan,nullptr,&interfaces)==ERROR_SUCCESS) {
      for(DWORD i=0;i<interfaces->dwNumberOfItems;i++) {
        DWORD length=0; PVOID data=nullptr; WLAN_OPCODE_VALUE_TYPE type;
        DWORD code=WlanQueryInterface(wlan,&interfaces->InterfaceInfo[i].InterfaceGuid,wlan_intf_opcode_current_connection,nullptr,&length,&data,&type);
        if(code==ERROR_SUCCESS && data) {
          auto info=static_cast<WLAN_CONNECTION_ATTRIBUTES*>(data);
          if(info->isState==wlan_interface_state_connected) {
            wifiFound=true;
            const auto& a=info->wlanAssociationAttributes;
            add("Wi-Fi SSID",std::string(reinterpret_cast<const char*>(a.dot11Ssid.ucSSID),a.dot11Ssid.uSSIDLength));
            char mac[32]{}; snprintf(mac,sizeof(mac),"%02X:%02X:%02X:%02X:%02X:%02X",a.dot11Bssid[0],a.dot11Bssid[1],a.dot11Bssid[2],a.dot11Bssid[3],a.dot11Bssid[4],a.dot11Bssid[5]);
            add("Wi-Fi BSSID",mac);
            add("Wi-Fi signal quality",std::to_string(a.wlanSignalQuality)+"% (driver quality; not RSSI dBm)",a.wlanSignalQuality/100.0);
            add("Wi-Fi receive / transmit link",std::to_string(a.ulRxRate/1000)+" / "+std::to_string(a.ulTxRate/1000)+" Mbps");
            DWORD channelSize=0; PVOID channelData=nullptr;
            if(WlanQueryInterface(wlan,&interfaces->InterfaceInfo[i].InterfaceGuid,wlan_intf_opcode_channel_number,nullptr,&channelSize,&channelData,&type)==ERROR_SUCCESS && channelData) { add("Wi-Fi channel",std::to_string(*static_cast<ULONG*>(channelData))); WlanFreeMemory(channelData); }
          }
          WlanFreeMemory(data);
        } else if(code==ERROR_ACCESS_DENIED) add("Wi-Fi identifiers","Enable Windows Location access for desktop apps",-1,"permissionRequired");
      }
      WlanFreeMemory(interfaces);
    }
    WlanCloseHandle(wlan,nullptr);
  }
  if(!wifiFound) add("Wi-Fi connection","No accessible connected WLAN interface",-1,"temporarilyUnavailable");
  add("Display resolution",std::to_string(GetSystemMetrics(SM_CXSCREEN))+" x "+std::to_string(GetSystemMetrics(SM_CYSCREEN)));
  return rows;
}
// WinMM recording remains in memory. Timers keep the Flutter message loop responsive.
struct MicrophoneTest {
  HWAVEIN input=nullptr;
  WAVEHDR header{};
  std::vector<char> pcm;
  std::vector<char> wave;
  HWND window=nullptr;
  bool playing=false;
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result;
};
inline MicrophoneTest& Mic() { static MicrophoneTest state; return state; }
inline void FinishMic(const std::string& message) {
  auto& state=Mic();
  if(state.window) KillTimer(state.window,1);
  if(state.input) { waveInReset(state.input); waveInUnprepareHeader(state.input,&state.header,sizeof(state.header)); waveInClose(state.input); state.input=nullptr; }
  PlaySoundW(nullptr,nullptr,0);
  state.pcm.clear(); state.wave.clear(); state.playing=false;
  if(state.result) { state.result->Success(flutter::EncodableValue(message)); state.result.reset(); }
}
inline LRESULT CALLBACK MicProc(HWND hwnd,UINT message,WPARAM w,LPARAM l) {
  if(message==WM_TIMER) {
    auto& state=Mic();
    if(state.playing) { FinishMic("Recorded and played back 3 seconds locally. Confirm audio quality yourself."); return 0; }
    waveInStop(state.input); waveInReset(state.input);
    DWORD n=state.header.dwBytesRecorded;
    waveInUnprepareHeader(state.input,&state.header,sizeof(state.header)); waveInClose(state.input); state.input=nullptr;
    if(n==0) { FinishMic("No microphone samples received. Check Windows microphone privacy settings and input device."); return 0; }
    state.wave.resize(44+n); char* b=state.wave.data();
    auto put32=[&](int offset,DWORD v){ memcpy(b+offset,&v,4); };
    auto put16=[&](int offset,WORD v){ memcpy(b+offset,&v,2); };
    memcpy(b,"RIFF",4); put32(4,36+n); memcpy(b+8,"WAVEfmt ",8); put32(16,16); put16(20,1); put16(22,1); put32(24,16000); put32(28,32000); put16(32,2); put16(34,16); memcpy(b+36,"data",4); put32(40,n); memcpy(b+44,state.pcm.data(),n);
    if(!PlaySoundA(state.wave.data(),nullptr,SND_MEMORY|SND_ASYNC|SND_NODEFAULT)) { FinishMic("Recording captured, but playback device could not play it."); return 0; }
    state.playing=true; SetTimer(hwnd,1,3300,nullptr); return 0;
  }
  return DefWindowProcW(hwnd,message,w,l);
}
inline void StartMic(std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  auto& state=Mic();
  if(state.result) { result->Error("BUSY","Microphone test already active"); return; }
  if(!state.window) {
    WNDCLASSW c{}; c.lpfnWndProc=MicProc; c.hInstance=GetModuleHandleW(nullptr); c.lpszClassName=L"AZUtilityMicrophone";
    RegisterClassW(&c); state.window=CreateWindowExW(0,c.lpszClassName,L"",0,0,0,0,0,HWND_MESSAGE,nullptr,c.hInstance,nullptr);
  }
  if(!state.window) { result->Error("AUDIO","Could not initialize recording timer"); return; }
  state.result=std::move(result);
  WAVEFORMATEX format{}; format.wFormatTag=WAVE_FORMAT_PCM; format.nChannels=1; format.nSamplesPerSec=16000; format.wBitsPerSample=16; format.nBlockAlign=2; format.nAvgBytesPerSec=32000;
  if(waveInOpen(&state.input,WAVE_MAPPER,&format,0,0,CALLBACK_NULL)!=MMSYSERR_NOERROR) { state.input=nullptr; FinishMic("Microphone unavailable or permission denied. Check Windows desktop microphone access."); return; }
  state.pcm.assign(96000,0); state.header={}; state.header.lpData=state.pcm.data(); state.header.dwBufferLength=static_cast<DWORD>(state.pcm.size());
  if(waveInPrepareHeader(state.input,&state.header,sizeof(state.header))!=MMSYSERR_NOERROR || waveInAddBuffer(state.input,&state.header,sizeof(state.header))!=MMSYSERR_NOERROR || waveInStart(state.input)!=MMSYSERR_NOERROR) { FinishMic("Microphone recording could not start."); return; }
  SetTimer(state.window,1,3000,nullptr);
}
inline std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> Register(flutter::FlutterEngine* engine) {
  auto channel=std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(engine->messenger(),"com.az.utility/native",&flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call,auto result) {
    using V=flutter::EncodableValue;
    if(call.method_name()=="snapshot") result->Success(V(Snapshot()));
    else if(call.method_name()=="speaker") { MessageBeep(MB_OK); result->Success(V("Requested Windows notification sound. Confirm audibility yourself.")); }
    else if(call.method_name()=="microphone") StartMic(std::move(result));
    else if(call.method_name()=="cancelHardware") { FinishMic("Microphone test cancelled"); result->Success(); }
    else if(call.method_name()=="recycle" || call.method_name()=="shareFile") {
      const auto* args=std::get_if<flutter::EncodableMap>(call.arguments());
      if(!args || args->find(V("path"))==args->end() || !std::holds_alternative<std::string>(args->at(V("path")))) { result->Error("PATH","Missing file path"); return; }
      auto path=Wide(std::get<std::string>(args->at(V("path"))));
      if(path.empty() || GetFileAttributesW(path.c_str())==INVALID_FILE_ATTRIBUTES) { result->Error("PATH","File no longer accessible"); return; }
      if(call.method_name()=="recycle") {
        path.push_back(L'\0'); path.push_back(L'\0'); SHFILEOPSTRUCTW op{}; op.hwnd=GetActiveWindow(); op.wFunc=FO_DELETE; op.pFrom=path.c_str(); op.fFlags=FOF_ALLOWUNDO|FOF_WANTNUKEWARNING|FOF_NO_CONNECTED_ELEMENTS;
        int code=SHFileOperationW(&op);
        if(code || op.fAnyOperationsAborted) result->Error("RECYCLE","Recycle operation failed or was cancelled"); else result->Success();
      } else {
        PIDLIST_ABSOLUTE id=nullptr; HRESULT hr=SHParseDisplayName(path.c_str(),nullptr,&id,0,nullptr);
        IShellFolder* folder=nullptr; PCUITEMID_CHILD child=nullptr; IContextMenu* menu=nullptr;
        if(SUCCEEDED(hr)) hr=SHBindToParent(id,IID_PPV_ARGS(&folder),&child);
        HWND owner=GetActiveWindow();
        if(SUCCEEDED(hr)) hr=folder->GetUIObjectOf(owner,1,&child,IID_IContextMenu,nullptr,reinterpret_cast<void**>(&menu));
        if(SUCCEEDED(hr)) {
          HMENU popup=CreatePopupMenu(); menu->QueryContextMenu(popup,0,1,0x7fff,CMF_NORMAL);
          POINT point{}; GetCursorPos(&point); UINT selected=TrackPopupMenu(popup,TPM_RETURNCMD|TPM_RIGHTBUTTON,point.x,point.y,0,owner,nullptr);
          if(selected) { CMINVOKECOMMANDINFO info{}; info.cbSize=sizeof(info); info.hwnd=owner; info.lpVerb=MAKEINTRESOURCEA(selected-1); info.nShow=SW_SHOWNORMAL; hr=menu->InvokeCommand(&info); }
          DestroyMenu(popup);
        }
        if(menu) menu->Release(); if(folder) folder->Release(); if(id) CoTaskMemFree(id);
        if(FAILED(hr)) result->Error("SHARE","Windows file menu unavailable"); else result->Success(V("Choose Share or Send to in the Windows file menu."));
      }
    }
    else if(call.method_name()=="vibrate" || call.method_name()=="sensors" || call.method_name()=="startSensors") result->Success(V("Unsupported: no sensor/vibration adapter on this Windows build"));
    else if(call.method_name()=="stopSensors") result->Success();
    else result->NotImplemented();
  }); return channel;
}
}
