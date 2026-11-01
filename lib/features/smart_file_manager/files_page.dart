import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:fl_chart/fl_chart.dart';
import '../../app/controller.dart';
import '../../core/models.dart';
import '../../core/widgets/dashboard_widgets.dart';
import 'file_service.dart';
import 'saf_page.dart';

class FilesPage extends ConsumerStatefulWidget {
  const FilesPage({super.key});
  @override ConsumerState<FilesPage> createState()=>_FilesPageState();
}
class _FilesPageState extends ConsumerState<FilesPage> {
  String? current; List<FileSystemEntity> entries=[]; String search='',category='All'; bool grid=false,descending=false; String sort='Name'; final selected=<String>{}; String? listingError;
  Future<void> choose() async {
    final path=await FilePicker.getDirectoryPath(dialogTitle:'Choose an accessible folder');
    if(path==null||!mounted) return;
    ref.read(controllerProvider).root=path; current=path; await load();
  }
  Future<void> load() async {
    try { final list=await Directory(current!).list(followLinks:false).take(10000).toList(); if(mounted) setState(() { entries=list; selected.clear(); listingError=null; }); }
    catch(e) { if(mounted) setState(()=>listingError=e.toString()); }
  }
  Future<String?> prompt(String title,{String initial=''}) async {
    final input=TextEditingController(text:initial);
    final value=await showDialog<String>(context:context,builder:(context)=>AlertDialog(title:Text(title),content:TextField(controller:input,autofocus:true,onSubmitted:(v)=>Navigator.pop(context,v)),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(context,input.text),child:const Text('Continue'))]));
    // Dialog closing animations may still reference the controller.
    return value;
  }
  Future<void> operation(String title,Future<void> Function(Cancellation) action) async {
    final app=ref.read(controllerProvider);
    await app.run(title,(token) async { await action(token); await app.db.save('files',title,{'items':selected.length}); });
    if(current!=null) await load();
  }
  @override Widget build(BuildContext context) {
    final app=ref.watch(controllerProvider);
    final filtered=entries.where((e)=>p.basename(e.path).toLowerCase().contains(search.toLowerCase())&&(category=='All'||classify(e.path)==category)).toList()..sort((a,b)=>descending?p.basename(b.path).compareTo(p.basename(a.path)):p.basename(a.path).compareTo(p.basename(b.path)));
    final categories=<String,int>{}; for(final file in app.files.index) { categories.update(file.category,(n)=>n+file.size,ifAbsent:()=>file.size); }
    final total=categories.values.fold<int>(0,(a,b)=>a+b);
    return PageBody(title:'Smart File Manager',subtitle:'Selected accessible folders only · Symlinks are never followed',children:[
      ActionWrap(children:[FilledButton.icon(onPressed:app.busy?null:choose,icon:const Icon(Icons.folder_open),label:const Text('Choose folder')),OutlinedButton(onPressed:app.busy||app.root==null?null:app.scan,child:const Text('Scan folder')),OutlinedButton(onPressed:app.busy||app.files.index.isEmpty?null:app.findDuplicates,child:const Text('Find duplicates')),OutlinedButton(onPressed:app.files.index.isEmpty?null:()=>showLarge(app.files.index),child:const Text('Largest files'))]),
      if(Platform.isAndroid) const Panel(child:Text('Android scoped storage applies. This browser only uses readable selected paths. For document-provider folders, use the SAF browser below; no access to other apps’ private data is requested.')),
      if(Platform.isAndroid) OutlinedButton(onPressed:()=>openSaf(),child:const Text('Open Android document-provider folder (SAF)')),
      if(total>0) Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('Indexed coverage: ${app.files.index.length} files · ${bytes(total)}'),const Text('This is the selected scan subset, not whole-volume capacity.'),SizedBox(height:160,child:PieChart(PieChartData(sections:[for(int i=0;i<categories.length;i++) PieChartSectionData(value:categories.values.elementAt(i).toDouble(),title:categories.keys.elementAt(i),radius:40,color:Colors.primaries[i%Colors.primaries.length])],centerSpaceRadius:40,pieTouchData:PieTouchData(touchCallback:(event,response) { final i=response?.touchedSection?.touchedSectionIndex; if(event.isInterestedForInteractions&&i!=null&&i>=0&&i<categories.length) setState(()=>category=categories.keys.elementAt(i)); })))),for(final entry in categories.entries) ListTile(title:Text(entry.key),trailing:Text(bytes(entry.value)),onTap:()=>showLarge(app.files.index.where((f)=>f.category==entry.key).toList()))])),
      if(current==null) const Panel(child:Padding(padding:EdgeInsets.all(24),child:Text('Choose a folder to browse real files. Scans are read-only. File changes always require an explicit action.')))
      else Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[IconButton(tooltip:'Parent folder',onPressed:current==app.root?null:()=>navigate(p.dirname(current!)),icon:const Icon(Icons.arrow_upward)),Expanded(child:SelectableText(current!)),IconButton(tooltip:'Refresh',onPressed:load,icon:const Icon(Icons.refresh)),IconButton(tooltip:'Grid or list',onPressed:()=>setState(()=>grid=!grid),icon:Icon(grid?Icons.view_list:Icons.grid_view))]),
        TextField(decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Search this folder'),onChanged:(v)=>setState(()=>search=v)),
        ActionWrap(children:[DropdownButton<String>(value:category,items:[for(final c in ['All','Images','Videos','Audio','Documents','Archives','Other']) DropdownMenuItem(value:c,child:Text(c))],onChanged:(v)=>setState(()=>category=v!)),TextButton(onPressed:()=>setState(()=>descending=!descending),child:Text(descending?'Name Z–A':'Name A–Z')),TextButton(onPressed:app.busy?null:()=>newFolder(),child:const Text('New folder')),if(selected.isNotEmpty) ...[Text('${selected.length} selected'),TextButton(onPressed:app.busy?null:()=>transfer(false),child:const Text('Copy')),TextButton(onPressed:app.busy?null:()=>transfer(true),child:const Text('Move')),TextButton(onPressed:app.busy?null:zip,child:const Text('Create ZIP')),TextButton(onPressed:app.busy?null:remove,child:const Text('Delete'))]]),
        if(listingError!=null) Text(listingError!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
        if(filtered.isEmpty) const Padding(padding:EdgeInsets.all(24),child:Text('No accessible matching entries.')),
        SizedBox(height:480,child:grid?GridView.builder(gridDelegate:SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent:200,mainAxisExtent:150),itemCount:filtered.length,itemBuilder:(context,i)=>fileTile(filtered[i],true)):ListView.builder(itemCount:filtered.length,itemBuilder:(context,i)=>fileTile(filtered[i],false))),
      ])),
      if(app.duplicateGroups.isNotEmpty) Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[const Text('Verified SHA-256 duplicate groups — review copies before deleting'),for(final group in app.duplicateGroups.take(100)) ExpansionTile(title:Text('${group.length} copies · ${bytes(group.first.size*(group.length-1))} potentially reclaimable'),children:[for(final file in group) ListTile(title:Text(p.basename(file.path)),subtitle:Text(file.path),onTap:()=>OpenFilex.open(file.path))])])),
    ]);
  }
  Widget fileTile(FileSystemEntity entity,bool compact) {
    final name=p.basename(entity.path); final folder=entity is Directory; final link=entity is Link;
    return ListTile(selected:selected.contains(entity.path),leading:Checkbox(value:selected.contains(entity.path),onChanged:folder||link?null:(v)=>setState(()=>v==true?selected.add(entity.path):selected.remove(entity.path))),title:Text(name,maxLines:compact?3:1,overflow:TextOverflow.ellipsis),subtitle:Text(folder?'Folder':link?'Symlink · not followed':classify(name)),onTap:link?null:()=>folder?navigate(entity.path):OpenFilex.open(entity.path),trailing:PopupMenuButton<String>(onSelected:(action)=>fileAction(action,entity),itemBuilder:(_)=>[for(final action in ['Details','Rename',if(!folder&&!link) 'Inspect ZIP',if(!folder&&!link) 'Extract ZIP']) PopupMenuItem(value:action,child:Text(action))]));
  }
  Future<void> navigate(String path) async { current=path; await load(); }
  Future<void> newFolder() async { final name=await prompt('New folder name'); if(name!=null) await operation('Create folder',(_)=>Directory(safeChild(current!,name)).create()); }
  Future<void> transfer(bool move) async { final destination=await FilePicker.getDirectoryPath(); if(destination==null) return; final sources=selected.toList(); await operation(move?'Move files':'Copy files',(token) async { for(final source in sources) { await ref.read(controllerProvider).files.copy(source,safeChild(destination,p.basename(source)),token,move:move); } }); }
  Future<void> remove() async {
    final targets=selected.toList();
    final confirmed=await showDialog<bool>(context:context,builder:(context)=>AlertDialog(title:Text('Permanently delete ${targets.length} files?'),content:const Text('These files will not go to a recycle bin. Recovery is not guaranteed. No folders are deleted.'),actions:[TextButton(onPressed:()=>Navigator.pop(context,false),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(context,true),child:const Text('Permanently delete'))]));
    if(confirmed==true) await operation('Delete files',(token) async { for(final path in targets) { token.check(); await ref.read(controllerProvider).files.deleteFile(path); } });
  }
  Future<void> zip() async { final name=await prompt('ZIP filename',initial:'Archive.zip'); if(name==null) return; final paths=selected.toList(); await operation('Create ZIP',(token)=>ref.read(controllerProvider).files.createZip(paths,safeChild(current!,name),token)); }
  Future<void> fileAction(String action,FileSystemEntity entity) async {
    final service=ref.read(controllerProvider).files;
    if(action=='Rename') { final name=await prompt('Rename',initial:p.basename(entity.path)); if(name!=null) await operation('Rename',(_)=>service.rename(entity.path,name)); }
    if(action=='Details') { final stat=await entity.stat(); if(mounted) await showDialog<void>(context:context,builder:(context)=>AlertDialog(title:Text(p.basename(entity.path)),content:SelectableText('${entity.path}\n${bytes(stat.size)}\nModified: ${stat.modified}\nType: ${stat.type}'),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Close'))])); }
    if(action=='Inspect ZIP') await operation('Inspect ZIP',(token) async { final names=await service.inspectZip(entity.path); token.check(); if(mounted) await showDialog<void>(context:context,builder:(context)=>AlertDialog(title:const Text('Archive contents'),content:SizedBox(width:600,height:400,child:ListView(children:names.map((n)=>Text(n)).toList())),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Close'))])); });
    if(action=='Extract ZIP') { final name=await prompt('New extraction folder',initial:p.basenameWithoutExtension(entity.path)); if(name!=null) await operation('Extract ZIP',(token)=>service.extractZip(entity.path,safeChild(current!,name),token)); }
  }
  Future<void> showLarge(List<IndexedFile> input) async {
    final list=input.toList()..sort((a,b)=>b.size.compareTo(a.size));
    await showDialog<void>(context:context,builder:(context)=>AlertDialog(title:const Text('Files by size'),content:SizedBox(width:700,height:500,child:ListView.builder(itemCount:list.length,itemBuilder:(context,i)=>ListTile(title:Text(p.basename(list[i].path)),subtitle:Text(list[i].path),trailing:Text(bytes(list[i].size)),onTap:()=>OpenFilex.open(list[i].path)))),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Close'))]));
  }
  Future<void> openSaf() async {
    final app=ref.read(controllerProvider);
    await app.run('Choose Android folder',(token) async {
      final uri=await app.native.chooseTree();
      token.check();
      if(uri!=null&&mounted) await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>SafPage(uri:uri)));
    });
  }
}
