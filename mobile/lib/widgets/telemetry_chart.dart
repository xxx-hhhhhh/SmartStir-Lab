import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Plots only measured MQTT state samples. Missing seconds are NEVER synthesized.
class TelemetryChart extends StatelessWidget {
  const TelemetryChart({super.key, required this.samples});
  final List<Map<String,dynamic>> samples;

  @override
  Widget build(BuildContext context) {
    final valid=samples.where((s)=>
      s['pwm_percent'] is num &&
      DateTime.tryParse((s['sampled_at']??'').toString())!=null).toList();
    if(valid.isEmpty){
      return const SizedBox(height:130,child:Center(
        child:Text('—',style:TextStyle(color:Color(0xFF94A3B8),fontSize:28))));
    }
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      SizedBox(height:190,child:CustomPaint(
        painter:_TelemetryPainter(valid,Theme.of(context).colorScheme.primary),
        child:const SizedBox.expand())),
      const SizedBox(height:8),
      Row(children:[
        Container(width:12,height:3,color:Theme.of(context).colorScheme.primary),
        const SizedBox(width:6),
        const Text('PWM (%)',style:TextStyle(fontSize:11)),
        const Spacer(),
        Text('${valid.length} samples',style:const TextStyle(
          fontSize:11,color:Color(0xFF64748B))),
      ]),
    ]);
  }
}

class _TelemetryPainter extends CustomPainter {
  _TelemetryPainter(this.samples,this.color);
  final List<Map<String,dynamic>> samples;
  final Color color;

  @override
  void paint(Canvas canvas,Size size) {
    final left=34.0,right=10.0,top=14.0,bottom=30.0;
    final w=math.max(1.0,size.width-left-right);
    final h=math.max(1.0,size.height-top-bottom);
    final labels=TextPainter(textDirection:TextDirection.ltr);
    void text(String label,double x,double y,{TextAlign align=TextAlign.left}){
      labels.text=TextSpan(text:label,style:const TextStyle(
        color:Color(0xFF64748B),fontSize:10));
      labels.textAlign=align;
      labels.layout();
      labels.paint(canvas,Offset(x,y));
    }
    for(final value in [0,25,50,75,100]){
      final y=top+h*(1-value/100);
      canvas.drawLine(Offset(left,y),Offset(left+w,y),
        Paint()..color=const Color(0xFFE2E8F0)..strokeWidth=1);
      text('$value',2,y-7);
    }
    final times=samples.map((s)=>DateTime.parse(s['sampled_at'].toString())
      .millisecondsSinceEpoch.toDouble()).toList();
    final minTime=times.first,maxTime=times.last;
    final span=math.max(1000.0,maxTime-minTime);
    double x(int index)=>left+w*(times[index]-minTime)/span;
    double y(int index)=>top+h*(1-
       ((samples[index]['pwm_percent'] as num).toDouble().clamp(0.0,100.0)/100));
    final line=Paint()..color=color..strokeWidth=2.5
      ..style=PaintingStyle.stroke..strokeCap=StrokeCap.round;
    final path=Path()..moveTo(x(0),y(0));
    for(var i=1;i<samples.length;i++){
      final prevX=x(i-1),nextX=x(i);
      // A gap longer than 5s is visibly discontinuous, not invented data.
      if(times[i]-times[i-1]>5000){
        canvas.drawPath(path,line);
        path.reset();
        path.moveTo(nextX,y(i));
      }else{
        path.lineTo(nextX,y(i-1));
        path.lineTo(nextX,y(i));
      }
    }
    canvas.drawPath(path,line);
    canvas.drawCircle(Offset(x(samples.length-1),y(samples.length-1)),
      3.5,Paint()..color=color);
    final first=DateTime.fromMillisecondsSinceEpoch(minTime.toInt()).toLocal();
    final last=DateTime.fromMillisecondsSinceEpoch(maxTime.toInt()).toLocal();
    String t(DateTime v)=>
      '${v.hour.toString().padLeft(2,'0')}:${v.minute.toString().padLeft(2,'0')}:${v.second.toString().padLeft(2,'0')}';
    text(t(first),left,size.height-19);
    labels.text=TextSpan(text:t(last),style:const TextStyle(
      color:Color(0xFF64748B),fontSize:10));
    labels.layout();
    labels.paint(canvas,Offset(left+w-labels.width,size.height-19));
  }

  @override
  bool shouldRepaint(covariant _TelemetryPainter old)=>
    old.samples!=samples||old.color!=color;
}
