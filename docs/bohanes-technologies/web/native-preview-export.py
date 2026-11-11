from pathlib import Path
import re,subprocess,tempfile,shutil,sys
root=Path(__file__).resolve().parents[3]
native=root/'native/LazenskyCommanderApp'
out=Path(tempfile.mkdtemp(prefix='commander-web-native-'))
print('Temporary build directory:',out)
subprocess.run(['swift','build','--package-path',str(root/'native/LazenskyCommander'),'--scratch-path',str(out/'core'),'--target','LazenskyCommanderCore'],check=True)
def block(s,marker):
 i=s.index(marker);p=s.index('{',i);d=1;j=p+1
 while d:
  if s[j]=='{':d+=1
  elif s[j]=='}':d-=1
  j+=1
 return s[i:j]+'\n'
brand=(native/'Shared/CommanderBrandAssets.swift').read_text()
mark=str(native/'Shared/BrandAssets.xcassets/BrandCircularMark.imageset/BrandCircularMark-384.png')
brand=brand.replace('import SwiftUI','import SwiftUI\nimport AppKit').replace('Image(circularMarkName)',f'Image(nsImage: NSImage(contentsOfFile: "{mark}")!)').replace('guard let url = Bundle.main.url(forResource: name, withExtension: "json") else { return nil }',f'let url = URL(fileURLWithPath: "{root}/assets/icons/lazensky-v1/" + name + ".json")')
style=(native/'LazenskyCommanderApp/CommanderDashboardStyle.swift').read_text()
style=style[:style.index('struct CommanderOpenScheduleAuditAction')]+block(style,'extension Color {')
widget=(native/'LazenskyCommanderLiveActivity/LazenskyCommanderHomeWidget.swift').read_text()
widgets=''
for m in ['struct CommanderHomeWidgetEntry:','private enum CommanderWidgetCountdownText','private enum CommanderWidgetTokens','private struct CommanderWidgetState','private struct CommanderWidgetBrandRow','private struct CommanderSmallHomeWidget','private struct CommanderMediumHomeWidget','private struct CommanderWidgetCountdown:','private struct CommanderWidgetEmptyState','private struct CommanderDayOverviewWidgetView']:
 widgets+=block(widget,m)
widgets=widgets.replace('Image(CommanderBrandAssets.circularMarkName, bundle: .main)',f'Image(nsImage: NSImage(contentsOfFile: "{mark}")!)').replace('.containerBackground(CommanderWidgetTokens.backgroundGradient, for: .widget)', '.frame(maxWidth: .infinity, maxHeight: .infinity).background(CommanderWidgetTokens.backgroundGradient)').replace('.widgetURL(CommanderNavigation.todayURL)','')
# SwiftUI's .relative style uses the host Mac's wall clock during ImageRenderer.
# For deterministic marketing exports, calculate the text from the widget entry date instead.
widgets='private let commanderWebWidgetDemoNow = Date(timeIntervalSince1970: 1790148300)\n' + widgets
widgets=widgets.replace('Text(target, style: .relative)', 'Text(CommanderWidgetCountdownText.value(now: commanderWebWidgetDemoNow, target: target))')
activity=(native/'LazenskyCommanderLiveActivity/LazenskyCommanderLiveActivity.swift').read_text()
acts='private typealias CommanderProcedureDisplay = CommanderActivityPresentation\n'
for m in ['private enum CommanderActivityTokens','private struct CommanderProcedureLockScreenView','private struct CommanderProcedureDisplayHero','private struct CommanderProcedureDisplaySideStatus','private struct CommanderActivityDivider','private struct CommanderActivityEventFooter','private struct CommanderNextEventLine','private struct CommanderActivityCardStyle','private extension View {','private struct CommanderProcedureStatusText','private struct CommanderPresentationClock','private struct CommanderClampedCountdown','private enum CommanderTimingSize','private struct CommanderProcedurePhaseTiming','private enum CommanderAlarmTime','private extension Color {','private struct CommanderProcedureIslandCenter','private struct CommanderProcedureIslandTiming','private struct CommanderProcedureIslandReference','private struct CommanderProcedureIslandBottom']:
 acts+=block(activity,m)
acts=acts.replace('let context: ActivityViewContext<CommanderProcedureLiveActivityAttributes>','let display: CommanderProcedureDisplay')
acts=re.sub(r'    let (display|preview) = CommanderProcedureDisplay.resolve\(\n.*?\n    \)\n','',acts,flags=re.S)
# System-hosted timer text also advances against the host wall clock. Keep the real native
# presentation layout, but freeze the exported countdown to the canonical web-demo time.
acts=acts.replace('CommanderSystemCountdown(target: target)', 'Text(commanderWebDemoCountdown(target))')
acts='''private let commanderWebDemoNow = Date(timeIntervalSince1970: 1790148300)
private func commanderWebDemoCountdown(_ target: Date) -> String {
  let minutes = max(0, Int(ceil(target.timeIntervalSince(commanderWebDemoNow) / 60)))
  return "\(minutes) min"
}
''' + acts
watch=(native/'LazenskyCommanderWatchApp/WatchCommanderView.swift').read_text()
watch=block(watch,'private struct WatchCommanderStateView').replace('ScrollView(.vertical) {','VStack(spacing: 0) {').replace('.defaultScrollAnchor(.top)','').replace('.contentMargins(.top, 0, for: .scrollContent)','').replace('.scrollIndicators(.hidden)','')
watch=watch.replace('timing.countdownText(at: liveState.now)', 'timing.target.map { "\\(max(0, Int(ceil($0.timeIntervalSince(liveState.now) / 60)))) min" }')
watchassets=(native/'LazenskyCommanderWatchApp/WatchVisualAssets.swift').read_text()
fixture='''
struct WatchCommanderModel { let cacheError: String? = nil; let transportError: String? = nil; let notificationError: String? = nil }
private struct ExportIsland: View {
 let display: CommanderProcedureDisplay
 var body: some View {
  VStack(spacing: 8) {
   HStack(alignment: .top) {
    CommanderBrandAssets.circularMark.resizable().scaledToFit().frame(width:24,height:24).padding(.leading,8)
    Spacer()
    CommanderProcedureIslandCenter(display:display)
    Spacer()
    CommanderProcedureIslandReference(display:display)
   }
   CommanderProcedureIslandBottom(display:display)
  }.padding(12).background(.black).clipShape(RoundedRectangle(cornerRadius:30))
 }
}
@main struct Export {
 @MainActor static func save<V: View>(_ name:String,_ view:V,width:CGFloat,height:CGFloat) throws {
  let content=view.frame(width:width,height:height).environment(\\.locale,Locale(identifier:"cs_CZ")).environment(\\.timeZone,TimeZone(identifier:"Europe/Prague")!).environment(\\.colorScheme,.dark)
  let renderer=ImageRenderer(content:content);renderer.scale=3
  guard let cg=renderer.cgImage else { fatalError(name) }
  let bitmap=NSBitmapImageRep(cgImage:cg)
  try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]+"/"+name+".png"))
 }
 @MainActor static func main() throws {
  for (name,symbol) in [("document","doc.text"),("convert","arrow.triangle.2.circlepath"),("check","checkmark.shield"),("bell","bell.badge.fill"),("calendar","calendar"),("clock","clock.fill")] {
   try save("symbol-"+name,Image(systemName:symbol).font(.system(size:30,weight:.semibold)).foregroundStyle(Color(commanderPresentationHex:"#65E5FF")),width:52,height:52)
  }
  let fmt=DateFormatter();fmt.locale=Locale(identifier:"en_US_POSIX");fmt.calendar=Calendar(identifier:.gregorian);fmt.timeZone=TimeZone(identifier:"Europe/Prague");fmt.dateFormat="yyyy-MM-dd'T'HH:mm:ss"
  guard let now=fmt.date(from:"2026-09-23T09:25:00") else { fatalError("web demo time") }
  let json="""
  {"schemaVersion":1,"scheduleVersion":1001,"updatedAt":"2026-09-23T07:25:00Z","stay":{"spa":"Rehabilitační sanatorium Darkov","dateFrom":"2026-09-22","dateTo":"2026-09-28"},"events":[
  {"stableId":"web-breakfast","date":"2026-09-23","start":"07:30","end":"08:00","title":"Snídaně","location":"Jídelna","kind":"meal","mealType":"Snídaně"},
  {"stableId":"web-iodobrom","date":"2026-09-23","start":"08:20","end":"08:40","title":"Jodobromová koupel","location":"Vodoléčba","kind":"procedure","procedureType":"Jodobromová koupel"},
  {"stableId":"web-ltv","date":"2026-09-23","start":"09:15","end":"09:45","title":"LTV","location":"Tělocvična","kind":"procedure","procedureType":"LTV"},
  {"stableId":"web-ultrasound","date":"2026-09-23","start":"10:15","end":"10:30","title":"Ultrazvuk","location":"Elektroléčba","kind":"procedure","procedureType":"Ultrazvuk"},
  {"stableId":"web-lunch","date":"2026-09-23","start":"12:00","end":"12:40","title":"Oběd","location":"Jídelna","kind":"meal","mealType":"Oběd"},
  {"stableId":"web-imoove","date":"2026-09-23","start":"14:10","end":"14:30","title":"iMoove","location":"Rehabilitace","kind":"procedure","procedureType":"iMoove"},
  {"stableId":"web-dinner","date":"2026-09-23","start":"17:30","end":"18:00","title":"Večeře","location":"Jídelna","kind":"meal","mealType":"Večeře"}],
  "settings":{"defaultLeadTimeMinutes":20,"procedureTypeOverrides":{},"mealOverrides":{}}}
  """
  let schedule=try JSONDecoder().decode(Schedule.self,from:Data(json.utf8))
  let snapshot=WatchScheduleSnapshot(schedule:schedule)
  let entry=CommanderHomeWidgetEntry(date:now,snapshot:snapshot)
  let state=CommanderWidgetState(entry:entry)
  try save("widget-medium",CommanderMediumHomeWidget(state:state).clipShape(RoundedRectangle(cornerRadius:24)),width:338,height:158)
  try save("widget-small",CommanderSmallHomeWidget(state:state).clipShape(RoundedRectangle(cornerRadius:24)),width:158,height:158)
  try save("widget-day",CommanderDayOverviewWidgetView(entry:entry).clipShape(RoundedRectangle(cornerRadius:24)),width:158,height:158)
  try save("commander-wordmark",CommanderGlassHeader(tab:""),width:370,height:70)
  try save("watch",WatchCommanderStateView(liveState:state.live,model:WatchCommanderModel()),width:205,height:251)
  let seed=CommanderAlarmEventSnapshot(stableId:"web-ltv",iconKey:"rehab",title:"LTV",location:"Tělocvična",kind:.procedure,startAt:"2026-09-23T09:15:00",endAt:"2026-09-23T09:45:00",leaveAt:"2026-09-23T08:55:00")
  let display=CommanderActivityPresentation.resolve(seed:seed,events:[seed],focusStableId:seed.stableId,presentationMode:.eventContext,at:now)
  try save("live-activity",CommanderProcedureLockScreenView(display:display).clipShape(RoundedRectangle(cornerRadius:24)),width:402,height:164)
  try save("dynamic-island",ExportIsland(display:display),width:370,height:170)
  let compact=HStack(spacing:75){CommanderBrandAssets.circularMark.resizable().scaledToFit().frame(width:20,height:20);CommanderProcedureIslandTiming(display:display,size:.compact)}.padding(.horizontal,16).frame(maxWidth:.infinity,maxHeight:.infinity).background(.black).clipShape(Capsule())
  try save("dynamic-island-compact",compact,width:230,height:40)
 }
}
'''
source='import Foundation\nimport SwiftUI\nimport AppKit\nimport WidgetKit\nimport LazenskyCommanderCore\n'+brand+style+widgets+acts+watch+watchassets+fixture
# A SwiftUI export host is used; the original native component layouts are retained.
(out/'NativeProductExport.swift').write_text(source)
modules=list((out/'core').rglob('LazenskyCommanderCore.swiftmodule'))
print('MODULES',modules)
objs=list((out/'core').rglob('Objects-normal/arm64/*.o'))
cmd=['swiftc','-parse-as-library','-I',str(modules[0].parent),str(out/'NativeProductExport.swift')]+[str(p) for p in objs]+['-o',str(out/'native-export')]
print('Compiling native views',len(objs),'core objects')
with (out/'export-build.log').open('w') as log: result=subprocess.run(cmd,stdout=log,stderr=log)
print('compile result',result.returncode)
if result.returncode:print((out/'export-build.log').read_text()[-13000:])

if result.returncode:
 raise SystemExit(result.returncode)
output = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else root/'docs/bohanes-technologies/web/site/native-ui'
output.mkdir(parents=True, exist_ok=True)
subprocess.run([str(out/'native-export'), str(output)], check=True)
shutil.copy2(root/'native/LazenskyCommanderApp/Shared/BrandAssets.xcassets/BrandCircularMark.imageset/BrandCircularMark-384.png',output/'commander-mark.png')
print('Native product exports saved:',output)
