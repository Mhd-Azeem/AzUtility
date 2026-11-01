#pragma once
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <winsock2.h>
#include <flutter/flutter_engine.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <iphlpapi.h>
#include <string>
#include <vector>
#include <memory>

namespace az {
inline std::string Utf8(const std::wstring& text) {
  if(text.empty()) return {};
  int count=WideCharToMultiByte(CP_UTF8,0,text.data(),static_cast<int>(text.size()),nullptr,0,nullptr,nullptr);
  std::string out(count,0); WideCharToMultiByte(CP_UTF8,0,text.data(),static_cast<int>(text.size()),out.data(),count,nullptr,nullptr); return out;
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
    }
  }
  ULONG length=16384; std::vector<unsigned char> buffer(length); auto adapters=reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
  ULONG code=GetAdaptersAddresses(AF_UNSPEC,GAA_FLAG_SKIP_ANYCAST|GAA_FLAG_SKIP_MULTICAST,nullptr,adapters,&length);
  if(code==ERROR_BUFFER_OVERFLOW) { buffer.resize(length); adapters=reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data()); code=GetAdaptersAddresses(AF_UNSPEC,GAA_FLAG_SKIP_ANYCAST|GAA_FLAG_SKIP_MULTICAST,nullptr,adapters,&length); }
  if(code==NO_ERROR) for(auto adapter=adapters;adapter;adapter=adapter->Next) if(adapter->OperStatus==IfOperStatusUp) add("Network adapter",Utf8(adapter->FriendlyName));
  add("Display resolution",std::to_string(GetSystemMetrics(SM_CXSCREEN))+" x "+std::to_string(GetSystemMetrics(SM_CYSCREEN)));
  return rows;
}
inline std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> Register(flutter::FlutterEngine* engine) {
  auto channel=std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(engine->messenger(),"com.az.utility/native",&flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([](const auto& call,auto result) {
    if(call.method_name()=="snapshot") result->Success(flutter::EncodableValue(Snapshot()));
    else if(call.method_name()=="speaker") { MessageBeep(MB_OK); result->Success(flutter::EncodableValue("Requested Windows notification sound. Confirm audibility yourself.")); }
    else if(call.method_name()=="vibrate" || call.method_name()=="sensors" || call.method_name()=="microphone") result->Success(flutter::EncodableValue("Unsupported by Windows adapter"));
    else result->NotImplemented();
  }); return channel;
}
}
