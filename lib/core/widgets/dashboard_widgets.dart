import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models.dart';

const cyan=Color(0xff58bdfe);
class Panel extends StatelessWidget {
  const Panel({super.key,required this.child,this.onTap});
  final Widget child;
  final VoidCallback? onTap;
  @override Widget build(BuildContext context)=>Card(clipBehavior:Clip.antiAlias,child:InkWell(onTap:onTap,child:Padding(padding:const EdgeInsets.all(20),child:child)));
}
class PageBody extends StatelessWidget {
  const PageBody({super.key,required this.title,required this.subtitle,required this.children});
  final String title,subtitle;
  final List<Widget> children;
  @override Widget build(BuildContext context)=>ListView(padding:EdgeInsets.all(MediaQuery.sizeOf(context).width<650?16:28),children:[Text(title,style:Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight:FontWeight.bold)),const SizedBox(height:6),Text(subtitle,style:Theme.of(context).textTheme.bodyMedium),const SizedBox(height:24),...children.map((w)=>Padding(padding:const EdgeInsets.only(bottom:16),child:w))]);
}
class MetricGrid extends StatelessWidget {
  const MetricGrid({super.key,required this.metrics});
  final List<Metric> metrics;
  @override Widget build(BuildContext context)=>LayoutBuilder(builder:(context,c) { final columns=c.maxWidth>1000?4:c.maxWidth>650?3:2; return Wrap(spacing:8,runSpacing:8,children:metrics.map((m)=>SizedBox(width:(c.maxWidth-(columns-1)*8)/columns,child:Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(m.label,style:Theme.of(context).textTheme.labelLarge),const SizedBox(height:12),Text(m.value,style:Theme.of(context).textTheme.titleMedium),if(m.ratio!=null)...[const SizedBox(height:12),LinearProgressIndicator(value:m.ratio!.clamp(0,1))],if(m.status!=CapabilityStatus.available) Text(m.status.name,style:const TextStyle(color:Colors.orange))])))).toList()); });
}
class LatencyChart extends StatelessWidget {
  const LatencyChart({super.key,required this.values});
  final List<double?> values;
  @override Widget build(BuildContext context) => SizedBox(height:190,child:values.whereType<double>().isEmpty?const Center(child:Text('Run a connection test to collect real TCP samples.')):LineChart(LineChartData(minY:0,gridData:const FlGridData(show:true,drawVerticalLine:false),titlesData:const FlTitlesData(show:false),borderData:FlBorderData(show:false),lineBarsData:[LineChartBarData(spots:[for(int i=0;i<values.length;i++) values[i]==null?FlSpot.nullSpot:FlSpot(i.toDouble(),values[i]!)],isCurved:false,color:cyan,barWidth:2,dotData:const FlDotData(show:false),belowBarData:BarAreaData(show:true,color:cyan.withValues(alpha:0.12)))])));
}
class ActionWrap extends StatelessWidget {
  const ActionWrap({super.key,required this.children}); final List<Widget> children;
  @override Widget build(BuildContext context)=>Wrap(spacing:10,runSpacing:10,children:children);
}
