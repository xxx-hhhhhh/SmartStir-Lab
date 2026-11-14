import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/app_preferences.dart';
import '../core/github_update_service.dart';
import 'lab_home_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _server = TextEditingController(text: 'https://smartstir-gateway-v13-production.up.railway.app');
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _busy = false;
  bool _register = false;
  bool _obscure = true;
  String? _error;

  Future<void> _submit() async {
    if (_busy) return;
    if (_register && _password.text != _confirmation.text) {
      setState(() => _error = L.t('password_mismatch'));
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final api = _register
          ? await SmartStirApi.register(_server.text, _username.text.trim(), _password.text)
          : await SmartStirApi.login(_server.text, _username.text.trim(), _password.text);
      if (!mounted) { api.close(); return; }
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LabHomePage(api: api)));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _server.dispose(); _username.dispose(); _password.dispose(); _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SizedBox(height: 16),
          const Center(child: Icon(Icons.science_outlined,size:72,color:Color(0xFF1B365D))),
          const SizedBox(height: 14),
          Text(L.t('app'),textAlign:TextAlign.center,
            style:const TextStyle(fontSize:30,fontWeight:FontWeight.w800,color:Color(0xFF1B365D))),
          const SizedBox(height: 5),
          Text('${L.t('subtitle')} · V1.3.1',
            textAlign: TextAlign.center,style: const TextStyle(color:Color(0xFF64748B))),
          const SizedBox(height: 24),
          Card(child: Padding(padding:const EdgeInsets.all(20),child:Column(
            crossAxisAlignment:CrossAxisAlignment.stretch,children:[
              Text(_register?L.t('register'):L.t('login'),
                style:const TextStyle(fontSize:20,fontWeight:FontWeight.w700)),
              const SizedBox(height:16),
              TextField(controller:_server,keyboardType:TextInputType.url,
                decoration:InputDecoration(labelText:L.t('server'),prefixIcon:const Icon(Icons.cloud_outlined))),
              const SizedBox(height:12),
              TextField(controller:_username,
                decoration:InputDecoration(labelText:L.t('username'),prefixIcon:const Icon(Icons.person_outline))),
              const SizedBox(height:12),
              TextField(controller:_password,obscureText:_obscure,
                onSubmitted:(_) { if (!_register) _submit(); },
                decoration:InputDecoration(labelText:L.t('password'),
                  helperText:_register?L.t('password_note'):null,
                  prefixIcon:const Icon(Icons.lock_outline),
                  suffixIcon:IconButton(
                    onPressed:()=>setState(()=>_obscure=!_obscure),
                    icon:Icon(_obscure?Icons.visibility_off:Icons.visibility)))),
              if(_register)...[
                const SizedBox(height:12),
                TextField(controller:_confirmation,obscureText:_obscure,
                  decoration:InputDecoration(labelText:L.t('confirm_password'),
                    prefixIcon:const Icon(Icons.verified_user_outlined))),
              ],
              if(_error != null)...[
                const SizedBox(height:12),
                Text(_error!,style:const TextStyle(color:Color(0xFFB91C1C))),
              ],
              const SizedBox(height:18),
              FilledButton(onPressed:_busy?null:_submit,
                child:Padding(padding:const EdgeInsets.all(12),
                  child:Text(_busy?L.t('loading'):_register?L.t('register'):L.t('login')))),
              TextButton(onPressed:_busy?null:()=>setState((){_register=!_register;_error=null;}),
                child:Text(_register?L.t('switch_login'):L.t('switch_register'))),
            ]))),
          const SizedBox(height:10),
          Row(mainAxisAlignment:MainAxisAlignment.center,children:[
            DropdownButton<String>(
              value:AppPrefs.language.value,
              items:const [
                DropdownMenuItem(value:'zh',child:Text('简体中文')),
                DropdownMenuItem(value:'en',child:Text('English')),
                DropdownMenuItem(value:'ja',child:Text('日本語'))
              ],
              onChanged:(v){if(v!=null)AppPrefs.setLanguage(v);}),
            const SizedBox(width:16),
            TextButton.icon(onPressed:()=>SmartStirUpdateService.showUpdateDialog(context),
              icon:const Icon(Icons.system_update_alt),label:Text(L.t('update'))),
          ]),
        ])),
    ))));
  }
}
