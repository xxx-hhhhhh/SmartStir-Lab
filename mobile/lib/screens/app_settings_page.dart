import 'package:flutter/material.dart';
import '../core/app_preferences.dart';

class AppSettingsPage extends StatelessWidget {
  const AppSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title:Text(L.t('settings'))),
      body: ListView(padding:const EdgeInsets.all(16),children:[
        Card(child:Padding(padding:const EdgeInsets.all(12),child:Column(
          crossAxisAlignment:CrossAxisAlignment.start,children:[
            ListTile(title:Text(L.t('language')),leading:const Icon(Icons.language)),
            ...['zh','en','ja'].map((code)=>RadioListTile<String>(
              value:code,groupValue:AppPrefs.language.value,
              title:Text(L.t(code)),onChanged:(v){if(v!=null)AppPrefs.setLanguage(v);},
            )),
          ]))),
        const SizedBox(height:12),
        Card(child:ValueListenableBuilder<bool>(
          valueListenable:AppPrefs.confirmStart,
          builder:(context,enabled,_)=>SwitchListTile(
            secondary:const Icon(Icons.verified_user_outlined),
            title:Text(L.t('confirmation')),
            subtitle:Text(L.t('confirmation_desc')),
            value:enabled,
            onChanged:(v)=>AppPrefs.setConfirmStart(v),
          ))),
        const SizedBox(height:12),
        Padding(padding:const EdgeInsets.all(12),
          child:Text(L.t('safety_note'),
            style:const TextStyle(fontSize:12,color:Color(0xFF64748B)))),
      ]),
    );
  }
}
