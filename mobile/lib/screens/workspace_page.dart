import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/app_preferences.dart';
import '../core/github_update_service.dart';
import 'app_settings_page.dart';
import 'login_page.dart';
import '../widgets/telemetry_chart.dart';

class WorkspacePage extends StatefulWidget {
  const WorkspacePage({super.key,required this.api});
  final SmartStirApi api;
  @override
  State<WorkspacePage> createState()=>_WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  Timer? _timer;
  int _tab=0;
  int _pending=0;
  int _generation=0;
  bool _refreshing=false;
  bool _stopPending=false;
  Map<String,dynamic>? _device;
  List<Map<String,dynamic>> _events=[];
  List<Map<String,dynamic>> _runs=[];
  List<Map<String,dynamic>> _samples=[];
  String? _selectedRunId;
  String? _sampleError;
  bool _loadingSamples=false;
  int _tick=0;
  DateTime _clock=DateTime.now();
  bool _loadingRuns=false;
  String? _exportingRunId;
  double _pwm=30;
  String? _error;
  String _action='';
  DateTime? _lastSeen;
  bool get _busy=>_pending>0;

  @override
  void initState(){
    super.initState();_refresh();
    _timer=Timer.periodic(const Duration(seconds:1),(_){
      if(!mounted)return;
      final tick=++_tick;
      setState(()=>_clock=DateTime.now()); // clock refresh is not a fabricated sample
      if(_tab==0)_refresh();
      if(_tab==1){
        _refreshSamples();
        if(tick%3==0)_refreshRuns();
      }
    });
  }
  @override
  void dispose(){_timer?.cancel();widget.api.close();super.dispose();}

  Future<void> _refresh() async {
    if(_refreshing)return;
    _refreshing=true;
    try{
      final result=await widget.api.device();
      if(!mounted)return;
      setState(()=>_device=result);
      _lastSeen=DateTime.now();
      _error=null;
    }catch(e){if(mounted)setState(()=>_error=e.toString());}
    finally{_refreshing=false;}
  }

  Future<void> _refreshEvents() async {
    try {
      final events=await widget.api.events();
      if(mounted)setState(()=>_events=events);
    }catch(e){if(mounted)setState(()=>_error=e.toString());}
  }


  Future<void> _refreshRuns() async {
    if(_loadingRuns)return;
    setState(()=>_loadingRuns=true);
    try{
      final records=await widget.api.experimentRuns();
      if(mounted){
        final previous=_selectedRunId;
        setState((){
          _runs=records;
          if(previous==null&&records.isNotEmpty){
            _selectedRunId=records.first['id'].toString();
          }
        });
        await _refreshSamples();
      }
    }catch(e){
      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content:Text('${L.t('error')}: $e')));
      }
    }finally{
      if(mounted)setState(()=>_loadingRuns=false);
    }
  }

  Future<void> _refreshSamples() async {
    final runId=_selectedRunId;
    if(runId==null||_loadingSamples)return;
    _loadingSamples=true;
    try{
      final actual=await widget.api.experimentSamples(runId);
      if(mounted&&runId==_selectedRunId){
        setState((){
          _samples=actual;
          _sampleError=null;
        });
      }
    }catch(e){
      if(mounted&&runId==_selectedRunId){
        setState(()=>_sampleError=e.toString());
      }
    }finally{_loadingSamples=false;}
  }

  Future<void> _reviewRun(String id) async {
    if(_selectedRunId==id)return;
    setState((){
      _selectedRunId=id;
      _samples=[];
      _sampleError=null;
    });
    await _refreshSamples();
  }
  Future<void> _exportRun(String runId) async {
    if(_exportingRunId!=null)return;
    setState(()=>_exportingRunId=runId);
    try{
      final data=await widget.api.experimentCsv(runId);
      if(!mounted)return;
      final fileName='SmartStir-${widget.api.deviceId}-$runId.csv';
      await SharePlus.instance.share(ShareParams(
        files:[XFile.fromData(Uint8List.fromList(data),mimeType:'text/csv')],
        fileNameOverrides:[fileName],
        title:L.t('export_csv'),
      ));
    }catch(e){
      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content:Text('${L.t('export_failed')}: $e')));
      }
    }finally{
      if(mounted)setState(()=>_exportingRunId=null);
    }
  }

  String _formatRunTime(dynamic raw) {
    if(raw==null)return '—';
    final parsed=DateTime.tryParse(raw.toString());
    if(parsed==null)return raw.toString();
    return parsed.toLocal().toString().split('.').first;
  }

  Widget _runsTab()=>RefreshIndicator(
    onRefresh:_refreshRuns,
    child:ListView(padding:const EdgeInsets.all(20),children:[
      Row(children:[
        Expanded(child:Text(L.t('experiments'),
          style:Theme.of(context).textTheme.headlineSmall)),
        IconButton(onPressed:_loadingRuns?null:_refreshRuns,
          icon:const Icon(Icons.refresh),tooltip:L.t('refresh')),
      ]),
      const SizedBox(height:8),
      Text(L.t('csv_note'),style:const TextStyle(
        color:Color(0xFF64748B),fontSize:12)),
      const SizedBox(height:8),
      Text(L.t('updating_every_second'),style:const TextStyle(
        color:Color(0xFF64748B),fontSize:12)),
      const SizedBox(height:14),
      if(_selectedRunId!=null)Card(child:Padding(
        padding:const EdgeInsets.all(16),
        child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
          Text(L.t('live_monitor'),style:Theme.of(context).textTheme.titleMedium),
          const SizedBox(height:12),
          TelemetryChart(samples:_samples,
            intervalMs:_runs.where((r)=>r['id'].toString()==_selectedRunId)
                .map((r)=>r['sample_interval_ms'] is int
                    ?r['sample_interval_ms'] as int:3000)
                .firstOrNull??3000),
          const SizedBox(height:12),
          if(_sampleError!=null)Text(_sampleError!,
            style:const TextStyle(color:Colors.red,fontSize:12)),
          Text(L.t('live_samples'),style:Theme.of(context).textTheme.titleSmall),
          if(_samples.isEmpty)Padding(
            padding:const EdgeInsets.symmetric(vertical:12),
            child:Text(L.t('sampling_empty'))),
          if(_samples.isNotEmpty)SingleChildScrollView(
            scrollDirection:Axis.horizontal,
            child:DataTable(
              columnSpacing:16,
              headingRowHeight:36,
              dataRowMinHeight:34,
              dataRowMaxHeight:38,
              columns:[
                DataColumn(label:Text(L.t('latest_received'))),
                DataColumn(label:Text(L.t('pwm'))),
                DataColumn(label:Text(L.t('rpm'))),
                DataColumn(label:Text(L.t('motor'))),
              ],
              rows:_samples.reversed.take(12).map((sample){
                final dt=DateTime.tryParse(sample['sampled_at'].toString())?.toLocal();
                final stamp=dt==null?'—':
                   '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}:${dt.second.toString().padLeft(2,'0')}';
                return DataRow(cells:[
                  DataCell(Text(stamp)),
                  DataCell(Text(sample['pwm_percent']==null?'—':
                    '${sample['pwm_percent']}%')),
                  DataCell(Text(sample['actual_rpm']==null?'—':
                    sample['actual_rpm'].toString())),
                  DataCell(Text(L.t(sample['motor_enabled']==true?'running':'stopped'))),
                ]);
              }).toList(),
            )),
        ]))),
      const SizedBox(height:14),
      if(_loadingRuns)const LinearProgressIndicator(),
      if(_runs.isEmpty&&!_loadingRuns)Card(child:Padding(
        padding:const EdgeInsets.all(24),
        child:Text(L.t('no_experiments')))),
      ..._runs.map((r){
        final id=(r['id']??'').toString();
        final selected=id==_selectedRunId;
        final ended=r['ended_at']!=null;
        final count=r['sample_count']??0;
        final reason=r['end_reason']?.toString();
        final status=ended?reason=='signal_lost'
            ?L.t('signal_lost'):L.t('record_finished'):L.t('recording');
        return Card(color:selected?const Color(0xFFF0F6FC):null,
          child:Padding(padding:const EdgeInsets.all(10),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            ListTile(
              contentPadding:const EdgeInsets.symmetric(horizontal:8),
              leading:Icon(ended?Icons.history:Icons.fiber_manual_record,
                color:ended?Colors.grey:Colors.green),
              title:Text('${L.t('record_started')}: ${_formatRunTime(r['started_at'])}'),
              subtitle:Text('$status · ${L.t('sample_count')}: $count'),
            ),
            if(ended)Padding(padding:const EdgeInsets.only(left:8,bottom:6),
              child:Text('${L.t('record_ended')}: ${_formatRunTime(r['ended_at'])}',
                style:const TextStyle(fontSize:12,color:Color(0xFF64748B)))),
            Row(mainAxisAlignment:MainAxisAlignment.end,children:[
              TextButton.icon(
                onPressed:()=>_reviewRun(id),
                icon:const Icon(Icons.show_chart),
                label:Text(L.t('replay_run')),
              ),
              TextButton.icon(
                onPressed:_exportingRunId==null?()=>_exportRun(id):null,
                icon:_exportingRunId==id
                    ?const SizedBox(width:16,height:16,
                       child:CircularProgressIndicator(strokeWidth:2))
                    :const Icon(Icons.file_download_outlined),
                label:Text(_exportingRunId==id
                    ?L.t('exporting_csv'):L.t('export_csv')),
              ),
            ]),
          ])));
      }),
    ]),
  );

  Future<void> _send(String command,[int? value]) async {
    if(_busy&&command!='STOP')return;
    if(command=='STOP'&&_stopPending)return;
    if(command=='START'&&AppPrefs.confirmStart.value){
      final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
        title:Text(L.t('start_confirm_title')),
        content:Text(L.t('start_confirm_body')),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(L.t('cancel'))),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:Text(L.t('submit'))),
        ],
      ));
      if(ok!=true||!mounted)return;
    }
    final generation=++_generation;
    setState((){
      _pending++;
      if(command=='STOP')_stopPending=true;
      _action=L.t('command_wait');
    });
    try{
      final accepted=await widget.api.sendCommand(command,value:value);
      final id=accepted['command_id'];
      if(id is! String)throw ApiError('Server did not return command ID');
      var status='PENDING';
      String detail='';
      for(var i=0;i<12&&status=='PENDING';i++){
        await Future<void>.delayed(const Duration(milliseconds:900));
        final row=await widget.api.commandStatus(id);
        status=(row['status']??'PENDING').toString();
        final ack=row['ack_json'];
        if(ack is String&&ack.isNotEmpty){
          try{
            final decoded=jsonDecode(ack) as Map<String,dynamic>;
            detail=(decoded['error_code']??'').toString();
          }catch(_){}
        }
      }
      if(mounted&&generation==_generation){
        setState(()=>_action='$command: $status${detail.isEmpty?'':' ($detail)'}');
      }
      await _refresh();
    }catch(e){
      if(mounted&&generation==_generation){
        setState(()=>_action='${L.t('error')}: $e');
      }
    }finally{
      if(mounted){
        setState((){
          _pending--;
          if(command=='STOP')_stopPending=false;
        });
      }
    }
  }

  Future<void> _logout() async {
    try{await widget.api.logout();}catch(_){}
    if(!mounted)return;
    Navigator.pushAndRemoveUntil(context,
      MaterialPageRoute(builder:(_)=>const LoginPage()),(_)=>false);
  }

  @override
  Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(
      title:Text(widget.api.labName.isEmpty?L.t('app'):widget.api.labName),
      leading:IconButton(tooltip:L.t('back_labs'),
        icon:const Icon(Icons.arrow_back),onPressed:()=>Navigator.pop(context)),
      actions:[
        IconButton(tooltip:L.t('refresh'),onPressed:_refresh,icon:const Icon(Icons.refresh)),
        IconButton(tooltip:L.t('logout'),onPressed:_logout,icon:const Icon(Icons.logout)),
      ],
    ),
    body:SafeArea(child:Center(child:ConstrainedBox(
      constraints:const BoxConstraints(maxWidth:760),
      child:IndexedStack(index:_tab,children:[
        _controlTab(),_runsTab(),_eventsTab(),_settingsTab(),
      ]),
    ))),
    bottomNavigationBar:NavigationBar(selectedIndex:_tab,
      onDestinationSelected:(v){
        setState(()=>_tab=v);
        if(v==1)_refreshRuns();
        if(v==2)_refreshEvents();
      },
      destinations:[
        NavigationDestination(icon:const Icon(Icons.speed_outlined),label:L.t('control')),
        NavigationDestination(icon:const Icon(Icons.table_chart_outlined),label:L.t('experiments')),
        NavigationDestination(icon:const Icon(Icons.receipt_long_outlined),label:L.t('events')),
        NavigationDestination(icon:const Icon(Icons.settings_outlined),label:L.t('settings')),
      ]),
  );

  Widget _controlTab(){
    final online=_device?['online']==true&&_error==null;
    final recent=_lastSeen!=null&&
      DateTime.now().difference(_lastSeen!)<const Duration(seconds:12);
    final motor=_device?['motor_enabled']==true;
    final pwm=_device?['pwm_percent'];
    final rpm=_device?['actual_rpm'];
    final canOperate=online&&recent&&!_busy;
    final reportedIntervalMs=_device?['sample_interval_ms'];
    final selectedSecs=reportedIntervalMs is int
        ? reportedIntervalMs~/1000:null;
    return RefreshIndicator(onRefresh:_refresh,child:ListView(
      padding:const EdgeInsets.all(20),children:[
        Text(widget.api.deviceId,style:Theme.of(context).textTheme.titleLarge),
        const SizedBox(height:14),
        if(_error!=null)Card(child:ListTile(
          leading:const Icon(Icons.error_outline,color:Colors.red),
          title:Text(_error!))),
        Card(child:Padding(padding:const EdgeInsets.all(20),child:Column(
          crossAxisAlignment:CrossAxisAlignment.start,children:[
            Row(children:[
              Icon(online?Icons.cloud_done:Icons.cloud_off,
                color:online?Colors.green:Colors.red),
              const SizedBox(width:8),
              Text(L.t(online?'online':'offline'),
                style:const TextStyle(fontSize:17,fontWeight:FontWeight.w700)),
            ]),
            const Divider(height:26),
            Row(children:[
              Expanded(child:_metric(L.t('motor'),
                !online?L.t('unknown'):motor?L.t('running'):L.t('stopped'))),
              Expanded(child:_metric(L.t('pwm'),online?'$pwm%':'—')),
            ]),
            const SizedBox(height:14),
            _metric(L.t('rpm'),rpm==null?L.t('rpm_absent'):'$rpm RPM'),
          ],
        ))),
        const SizedBox(height:12),
        Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(
          crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(L.t('sample_interval'),style:const TextStyle(
              fontWeight:FontWeight.w700)),
            const SizedBox(height:6),
            Text(L.t('sample_interval_hint'),style:const TextStyle(
              color:Color(0xFF64748B),fontSize:12)),
            const SizedBox(height:10),
            Wrap(spacing:8,runSpacing:8,children:
              [1,3,5,10].map((sec)=>ChoiceChip(
                label:Text('${sec}s'),
                selected:selectedSecs==sec,
                onSelected:canOperate?(_)=>_send('SET_SAMPLE_INTERVAL',sec):null,
              )).toList()),
          ]))),
        const SizedBox(height:12),
        Card(child:Padding(padding:const EdgeInsets.all(20),child:Column(
          crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            Row(children:[
              Expanded(child:Text(L.t('pwm'),
                style:const TextStyle(fontWeight:FontWeight.w700))),
              Text('${_pwm.round()}%',style:const TextStyle(
                fontSize:22,fontWeight:FontWeight.w800)),
            ]),
            Slider(value:_pwm,min:0,max:100,divisions:20,
              onChanged:_busy?null:(v)=>setState(()=>_pwm=v)),
            Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
              const Text('0%'),const Text('100%'),
            ]),
            const SizedBox(height:10),
            OutlinedButton.icon(
              onPressed:canOperate?()=>_send('SET_PWM',_pwm.round()):null,
              icon:const Icon(Icons.tune),label:Text(L.t('set_pwm'))),
            const SizedBox(height:12),
            FilledButton.icon(
              onPressed:canOperate&&_pwm>0?()=>_send('START'):null,
              icon:const Icon(Icons.play_arrow),label:Text(L.t('start')),
              style:FilledButton.styleFrom(minimumSize:const Size.fromHeight(48))),
            const SizedBox(height:9),
            OutlinedButton.icon(
              onPressed:_stopPending?null:()=>_send('STOP'),
              icon:const Icon(Icons.stop_circle_outlined),label:Text(L.t('stop')),
              style:OutlinedButton.styleFrom(
                foregroundColor:const Color(0xFFB91C1C),
                minimumSize:const Size.fromHeight(48))),
            if(_action.isNotEmpty)...[
              const SizedBox(height:12),
              Text(_action,style:const TextStyle(fontSize:12)),
            ],
          ],
        ))),
      ],
    ));
  }

  Widget _metric(String title,String value)=>Column(
    crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(title,style:const TextStyle(color:Color(0xFF64748B),fontSize:12)),
      const SizedBox(height:6),
      Text(value,style:const TextStyle(
        color:Color(0xFF1B365D),fontWeight:FontWeight.w800,fontSize:19)),
    ]);

  Widget _eventsTab()=>RefreshIndicator(onRefresh:_refreshEvents,child:ListView(
    padding:const EdgeInsets.all(20),children:[
      Text(L.t('events'),style:Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height:12),
      if(_events.isEmpty)Card(child:Padding(padding:const EdgeInsets.all(24),
        child:Text(L.t('no_events')))),
      ..._events.map((e){
        final unix=e['created_at'];
        final date=unix is int?DateTime.fromMillisecondsSinceEpoch(unix*1000).toLocal():null;
        final detail=e['data_json']?.toString()??'';
        return Card(child:ListTile(
          leading:const Icon(Icons.event_note_outlined),
          title:Text((e['kind']??'').toString()),
          subtitle:Text('${date?.toString().split('.').first??'—'}\n$detail',
            maxLines:4,overflow:TextOverflow.ellipsis),
        ));
      }),
    ],
  ));

  Widget _settingsTab()=>ListView(padding:const EdgeInsets.all(20),children:[
    ListTile(
      leading:const Icon(Icons.settings_outlined),
      title:Text(L.t('settings')),
      subtitle:Text(L.t('confirmation_desc')),
      trailing:const Icon(Icons.chevron_right),
      onTap:()=>Navigator.push(context,
        MaterialPageRoute(builder:(_)=>const AppSettingsPage())),
    ),
    ListTile(leading:const Icon(Icons.memory_outlined),title:Text(L.t('device_id')),
      subtitle:Text(widget.api.deviceId)),
    ListTile(leading:const Icon(Icons.dns_outlined),title:Text(L.t('server')),
      subtitle:Text(widget.api.baseUrl)),
    ListTile(leading:const Icon(Icons.system_update_alt),
      title:Text(L.t('update')),
      onTap:()=>SmartStirUpdateService.showUpdateDialog(context)),
    ListTile(leading:const Icon(Icons.logout),title:Text(L.t('logout')),
      onTap:_logout),
  ]);
}
