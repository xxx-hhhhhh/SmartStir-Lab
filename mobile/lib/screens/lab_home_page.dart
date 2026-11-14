import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/app_preferences.dart';
import '../core/github_update_service.dart';
import 'app_settings_page.dart';
import 'login_page.dart';
import 'workspace_page.dart';

class LabHomePage extends StatefulWidget {
  const LabHomePage({super.key,required this.api});
  final SmartStirApi api;
  @override
  State<LabHomePage> createState()=>_LabHomePageState();
}

class _LabHomePageState extends State<LabHomePage> {
  List<Map<String,dynamic>> _labs=[];
  List<Map<String,dynamic>> _invitations=[];
  final Map<String,List<Map<String,dynamic>>> _devices={};
  bool _loading=false;
  String? _error;

  @override
  void initState(){super.initState();_refresh();}
  @override
  void dispose(){widget.api.close();super.dispose();}

  Future<void> _refresh() async {
    if(_loading)return;
    setState((){_loading=true;_error=null;});
    try{
      final labs=await widget.api.labs();
      final invites=await widget.api.invitations();
      final devicePairs=await Future.wait(labs.map((l) async => MapEntry(
        l['id'].toString(),await widget.api.labDevices(l['id'].toString()))));
      if(!mounted)return;
      setState((){
        _labs=labs;_invitations=invites;
        _devices..clear()..addEntries(devicePairs);
      });
    }catch(e){if(mounted)setState(()=>_error=e.toString());}
    finally{if(mounted)setState(()=>_loading=false);}
  }

  Future<String?> _prompt(String title,String label) async {
    final controller=TextEditingController();
    final result=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
      title:Text(title),
      content:TextField(controller:controller,autofocus:true,
        decoration:InputDecoration(labelText:label)),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx),child:Text(L.t('cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(ctx,controller.text.trim()),
          child:Text(L.t('submit'))),
      ],
    ));
    // TextEditingController is intentionally released after the dialog closes.
    controller.dispose();
    return result?.trim().isNotEmpty==true?result!.trim():null;
  }

  Future<void> _perform(Future<void> Function() work) async {
    try {await work();if(mounted)await _refresh();}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content:Text('${L.t('error')}: $e')));}
  }

  Future<void> _createLab() async {
    final name=await _prompt(L.t('create_lab'),L.t('lab_name'));
    if(name==null||!mounted)return;
    await _perform(()async{await widget.api.createLab(name);});
  }

  Future<void> _invite(String labId) async {
    final username=await _prompt(L.t('invite'),L.t('invite_username'));
    if(username==null||!mounted)return;
    await _perform(()async{await widget.api.inviteMember(labId,username);});
  }

  Future<void> _addDevice(String labId) async {
    final id=TextEditingController();
    final label=TextEditingController();
    final code=TextEditingController();
    final data=await showDialog<Map<String,String>>(context:context,builder:(ctx)=>AlertDialog(
      title:Text(L.t('add_device')),
      scrollable:true,
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:id,autofocus:true,
          decoration:InputDecoration(labelText:L.t('device_id'))),
        const SizedBox(height:12),
        TextField(controller:label,decoration:InputDecoration(labelText:L.t('device_name'))),
        const SizedBox(height:12),
        TextField(controller:code,
          decoration:InputDecoration(labelText:L.t('pairing_code'))),
        const SizedBox(height:12),
        Text(L.t('pair_hint'),style:const TextStyle(fontSize:12,color:Color(0xFF64748B))),
      ]),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx),child:Text(L.t('cancel'))),
        FilledButton(onPressed:()=>Navigator.pop(ctx,{
          'id':id.text.trim(),'label':label.text.trim(),'code':code.text.trim()
        }),child:Text(L.t('submit'))),
      ],
    ));
    id.dispose();label.dispose();code.dispose();
    if(data==null||!mounted)return;
    await _perform(()async{
      await widget.api.addDevice(labId,data['id']!,data['code']!,data['label']!);
    });
  }

  Future<void> _respond(String id,bool accept) async {
    await _perform(()async{await widget.api.respondInvitation(id,accept);});
  }

  void _openDevice(Map<String,dynamic> device,String labName) {
    final controlApi=SmartStirApi(baseUrl:widget.api.baseUrl,token:widget.api.token);
    controlApi.selectDevice(device['device_id'].toString(),labName);
    Navigator.push(context,MaterialPageRoute(
      builder:(_)=>WorkspacePage(api:controlApi)));
  }

  Future<void> _logout() async {
    try{await widget.api.logout();}catch(_){}
    if(!mounted)return;
    Navigator.pushAndRemoveUntil(context,
      MaterialPageRoute(builder:(_)=>const LoginPage()),(_)=>false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:AppBar(title:Text(L.t('labs')),
        actions:[
          IconButton(tooltip:L.t('refresh'),icon:const Icon(Icons.refresh),onPressed:_refresh),
          IconButton(tooltip:L.t('settings'),icon:const Icon(Icons.settings_outlined),
            onPressed:()=>Navigator.push(context,
              MaterialPageRoute(builder:(_)=>const AppSettingsPage()))),
          IconButton(tooltip:L.t('logout'),icon:const Icon(Icons.logout),onPressed:_logout),
        ]),
      floatingActionButton:FloatingActionButton.extended(
        icon:const Icon(Icons.add),label:Text(L.t('create_lab')),onPressed:_createLab),
      body:RefreshIndicator(onRefresh:_refresh,child:ListView(
        padding:const EdgeInsets.fromLTRB(16,16,16,100),children:[
          if(_loading)const LinearProgressIndicator(),
          if(_error!=null)Card(child:ListTile(
            leading:const Icon(Icons.error_outline,color:Colors.red),
            title:Text(_error!))),
          if(_invitations.isNotEmpty)...[
            Text(L.t('invitations'),style:Theme.of(context).textTheme.titleLarge),
            const SizedBox(height:8),
            ..._invitations.map((invite)=>Card(child:ListTile(
              title:Text(invite['lab_name']?.toString()??''),
              subtitle:Text(invite['invited_by']?.toString()??''),
              trailing:Wrap(spacing:4,children:[
                TextButton(onPressed:()=>_respond(invite['id'].toString(),false),
                  child:Text(L.t('decline'))),
                FilledButton(onPressed:()=>_respond(invite['id'].toString(),true),
                  child:Text(L.t('accept'))),
              ]),
            ))),
            const SizedBox(height:20),
          ],
          if(_labs.isEmpty&&!_loading)Padding(
            padding:const EdgeInsets.symmetric(vertical:60),
            child:Center(child:Text(L.t('no_labs')))),
          ..._labs.map((lab){
            final labId=lab['id'].toString();
            final name=lab['name']?.toString()??'';
            final role=lab['role']?.toString()??'member';
            final devs=_devices[labId]??[];
            return Card(margin:const EdgeInsets.only(bottom:16),child:Padding(
              padding:const EdgeInsets.all(16),child:Column(
                crossAxisAlignment:CrossAxisAlignment.stretch,children:[
                  Row(children:[
                    const Icon(Icons.science_outlined,size:28,color:Color(0xFF1B365D)),
                    const SizedBox(width:8),
                    Expanded(child:Text(name,style:Theme.of(context).textTheme.titleLarge)),
                    Chip(label:Text(L.t(role=='owner'?'owner':'member'))),
                  ]),
                  const SizedBox(height:8),
                  Row(children:[
                    Text('${L.t('devices')}: ${devs.length}'),
                    const Spacer(),
                    if(role=='owner')TextButton.icon(
                      icon:const Icon(Icons.person_add_alt_1),
                      onPressed:()=>_invite(labId),label:Text(L.t('invite'))),
                  ]),
                  const Divider(),
                  if(devs.isEmpty)Padding(padding:const EdgeInsets.all(12),
                    child:Text(L.t('no_devices'))),
                  ...devs.map((device){
                    final online=device['online']==true;
                    return ListTile(
                      contentPadding:EdgeInsets.zero,
                      leading:Icon(Icons.memory,color:online?Colors.green:Colors.grey),
                      title:Text(device['label']?.toString()??device['device_id'].toString()),
                      subtitle:Text('${device['device_id']} · ${L.t(online?'online':'offline')}'),
                      trailing:const Icon(Icons.chevron_right),
                      onTap:()=>_openDevice(device,name),
                    );
                  }),
                  if(role=='owner')OutlinedButton.icon(
                    onPressed:()=>_addDevice(labId),
                    icon:const Icon(Icons.add_circle_outline),
                    label:Text(L.t('add_device'))),
                ],
              ))));
          }),
          const SizedBox(height:8),
          TextButton.icon(
            onPressed:()=>SmartStirUpdateService.showUpdateDialog(context),
            icon:const Icon(Icons.system_update_alt),label:Text(L.t('update'))),
        ],
      )),
    );
  }
}
