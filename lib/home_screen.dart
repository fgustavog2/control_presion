
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Box usersBox;
  late Box medBox;
  String? activeUserId;
  String brazo='Izquierdo';
  String pos='Sentado';
  
  final sisCtrl=TextEditingController(text:'120');
  final diaCtrl=TextEditingController(text:'80');
  final pulsoCtrl=TextEditingController(text:'72');
  final notasCtrl=TextEditingController();
  final nombreCtrl=TextEditingController();
  final edadCtrl=TextEditingController();
  String sexo='Masculino';

  @override
  void initState(){
    super.initState();
    usersBox=Hive.box('users');
    medBox=Hive.box('mediciones');
    if(usersBox.isNotEmpty) activeUserId=usersBox.keys.first.toString();
  }

  String categoria(int sis,int dia){
    if(sis>=180||dia>=120) return 'Crisis';
    if(sis>=140||dia>=90) return 'Etapa 2';
    if(sis>=130||dia>=80) return 'Etapa 1';
    if(sis>=120) return 'Elevada';
    return 'Normal';
  }
  Color catColor(String c){
    if(c=='Crisis'||c=='Etapa 2') return Colors.redAccent;
    if(c=='Etapa 1') return Colors.orangeAccent;
    if(c=='Elevada') return Colors.yellowAccent;
    return Colors.greenAccent;
  }

  void addUser(){
    if(nombreCtrl.text.trim().isEmpty) return;
    final id=DateTime.now().millisecondsSinceEpoch.toString();
    usersBox.put(id, {'id':id,'nombre':nombreCtrl.text.trim(),'edad':edadCtrl.text.trim(),'sexo':sexo,'creado':DateTime.now().toIso8601String()});
    activeUserId=id;
    nombreCtrl.clear(); edadCtrl.clear();
    setState((){});
    _guardarArchivos();
  }

  List<Map> getMeds(){
    if(activeUserId==null) return [];
    return medBox.values.where((m)=>m['userId']==activeUserId).map((e)=>Map.from(e)).toList()..sort((a,b)=>b['fecha'].compareTo(a['fecha']));
  }

  Future<void> _guardarArchivos() async {
    try{
      final dir=await getApplicationDocumentsDirectory();
      // por usuario
      for(var u in usersBox.values){
        final uid=u['id'];
        final safe=u['nombre'].toString().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'),'_');
        final meds=medBox.values.where((m)=>m['userId']==uid).toList();
        // json
        final jsonFile=File('\${dir.path}/registros_\$safe.json');
        await jsonFile.writeAsString(meds.toString());
        // csv
        List<List<dynamic>> rows=[['fecha','sistolica','diastolica','pulso','brazo','posicion','notas','categoria','usuario','edad','sexo']];
        for(var m in meds){
          rows.add([m['fecha'],m['sistolica'],m['diastolica'],m['pulso'],m['brazo'],m['posicion'],m['notas'],categoria(m['sistolica'],m['diastolica']),u['nombre'],u['edad'],u['sexo']]);
        }
        String csvStr=const ListToCsvConverter().convert(rows);
        await File('\${dir.path}/registros_\$safe.csv').writeAsString(csvStr);
      }
      // global
      final global={'users':usersBox.values.toList(),'mediciones':medBox.values.toList()};
      await File('\${dir.path}/registros_global.json').writeAsString(global.toString());
    }catch(e){ print(e); }
  }

  void guardarMed(){
    if(activeUserId==null){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Primero agregá un usuario'))); return; }
    int sis=int.tryParse(sisCtrl.text)??0;
    int dia=int.tryParse(diaCtrl.text)??0;
    if(sis==0||dia==0||sis<=dia){ ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Revisá valores'))); return; }
    final med={
      'fecha':DateTime.now().toIso8601String(),
      'sistolica':sis,'diastolica':dia,
      'pulso':pulsoCtrl.text,'brazo':brazo,'posicion':pos,'notas':notasCtrl.text,
      'userId':activeUserId
    };
    medBox.add(med);
    notasCtrl.clear();
    setState((){});
    _guardarArchivos();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Guardado para \${usersBox.get(activeUserId)['nombre']} - archivo local actualizado')));
  }

  Future<void> generarPDF() async {
    if(activeUserId==null) return;
    final user=usersBox.get(activeUserId);
    final meds=getMeds();
    final pdf=pw.Document();
    pdf.addPage(pw.Page(build:(pw.Context ctx){
      return pw.Column(children:[
        pw.Container(color: PdfColor.fromHex('#0F172A'), padding:pw.EdgeInsets.all(12), child:pw.Text('Informe Presión - \${user['nombre']}', style:pw.TextStyle(color: PdfColor.fromHex('#FFFFFF'), fontSize:16))),
        pw.SizedBox(height:10),
        pw.Text('Edad: \${user['edad']} | Sexo: \${user['sexo']} | Total: \${meds.length} | Fecha: \${DateTime.now().toString()}'),
        pw.SizedBox(height:10),
        pw.Table.fromTextArray(
          headers:['Fecha','Presión','Pulso','Brazo','Pos','Cat','Notas'],
          data: meds.map((m)=>[m['fecha'].toString().substring(0,16),'\${m['sistolica']}/\${m['diastolica']}',m['pulso'].toString(),m['brazo'],m['posicion'],categoria(m['sistolica'],m['diastolica']),m['notas']]).toList()
        )
      ]);
    }));
    await Printing.sharePdf(bytes: await pdf.save(), filename: 'Informe_\${user['nombre']}.pdf');
  }

  @override
  Widget build(BuildContext context){
    final users=usersBox.values.toList();
    final active=activeUserId!=null?usersBox.get(activeUserId):null;
    final meds=getMeds();
    return Scaffold(
      appBar: AppBar(title:Text('Control Presión Multiusuario'), backgroundColor: Color(0xFF1E293B)),
      body: SingleChildScrollView(
        padding:EdgeInsets.all(12),
        child: Column(children:[
          // usuarios
          Card(child: Padding(padding:EdgeInsets.all(12), child: Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
            Text('👥 Usuarios', style:TextStyle(fontWeight:FontWeight.bold)),
            SizedBox(height:8),
            Wrap(children: users.map<Widget>((u){
              bool isAct=u['id']==activeUserId;
              return Padding(padding:EdgeInsets.all(4), child: ChoiceChip(label:Text('\${u['nombre']} \${u['edad']}a'), selected:isAct, selectedColor: Color(0xFF93C5FD), onSelected:(_){ setState(()=>activeUserId=u['id']); }));
            }).toList()),
            Row(children:[
              Expanded(child: TextField(controller:nombreCtrl, decoration:InputDecoration(labelText:'Nombre'))),
              SizedBox(width:8),
              SizedBox(width:60, child: TextField(controller:edadCtrl, decoration:InputDecoration(labelText:'Edad'), keyboardType:TextInputType.number)),
              SizedBox(width:8),
              DropdownButton<String>(value:sexo, items:['Masculino','Femenino','Otro'].map((s)=>DropdownMenuItem(value:s, child:Text(s))).toList(), onChanged:(v)=>setState(()=>sexo=v!)),
              ElevatedButton(onPressed:addUser, child:Text('+ Agregar'))
            ])
          ]))),
          // stats
          Row(children:[
            Expanded(child: Card(child: Padding(padding:EdgeInsets.all(12), child: Column(children:[Text('Prom 7d', style:TextStyle(fontSize:10)), Text(_prom(meds,7), style:TextStyle(fontSize:18, fontWeight:FontWeight.bold))])))),
            Expanded(child: Card(child: Padding(padding:EdgeInsets.all(12), child: Column(children:[Text('Prom 30d', style:TextStyle(fontSize:10)), Text(_prom(meds,30), style:TextStyle(fontSize:18, fontWeight:FontWeight.bold))])))),
            Expanded(child: Card(child: Padding(padding:EdgeInsets.all(12), child: Column(children:[Text('Total', style:TextStyle(fontSize:10)), Text('\${meds.length}', style:TextStyle(fontSize:18, fontWeight:FontWeight.bold, color: Color(0xFF93C5FD)))])))),
          ]),
          // nueva medición - estilo oscuro igual a imagen
          Card(child: Padding(padding:EdgeInsets.all(16), child: Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
            Text('♡ Nueva medición para \${active!=null?active['nombre']:'--'}', style:TextStyle(fontWeight:FontWeight.bold)),
            SizedBox(height:12),
            Row(children:[
              Expanded(child: Column(children:[Text('Sistólica (mmHg)', style:TextStyle(fontSize:12, color:Colors.white70)), TextField(controller:sisCtrl, textAlign:TextAlign.center, style:TextStyle(fontSize:28, fontWeight:FontWeight.bold), keyboardType:TextInputType.number, decoration:InputDecoration(border:OutlineInputBorder(borderRadius:BorderRadius.circular(12))))])),
              SizedBox(width:12),
              Expanded(child: Column(children:[Text('Diastólica (mmHg)', style:TextStyle(fontSize:12, color:Colors.white70)), TextField(controller:diaCtrl, textAlign:TextAlign.center, style:TextStyle(fontSize:28, fontWeight:FontWeight.bold), keyboardType:TextInputType.number, decoration:InputDecoration(border:OutlineInputBorder(borderRadius:BorderRadius.circular(12))))])),
            ]),
            SizedBox(height:12),
            Row(children:[
              Expanded(child: TextField(controller:pulsoCtrl, decoration:InputDecoration(labelText:'Pulso (bpm)'))),
              SizedBox(width:12),
              Expanded(child: Column(crossAxisAlignment:CrossAxisAlignment.start, children:[Text('Brazo'), Row(children:[ChoiceChip(label:Text('Izq'), selected:brazo=='Izquierdo', onSelected:(_)=>setState(()=>brazo='Izquierdo')), SizedBox(width:4), ChoiceChip(label:Text('Der'), selected:brazo=='Derecho', onSelected:(_)=>setState(()=>brazo='Derecho'))])])),
            ]),
            Row(children:[
              Text('Posición:'), ChoiceChip(label:Text('Sentado'), selected:pos=='Sentado', onSelected:(_)=>setState(()=>pos='Sentado')), ChoiceChip(label:Text('Acostado'), selected:pos=='Acostado', onSelected:(_)=>setState(()=>pos='Acostado')), ChoiceChip(label:Text('De pie'), selected:pos=='De pie', onSelected:(_)=>setState(()=>pos='De pie')),
            ]),
            TextField(controller:notasCtrl, decoration:InputDecoration(labelText:'Notas')),
            SizedBox(height:12),
            SizedBox(width:double.infinity, child: ElevatedButton(style:ElevatedButton.styleFrom(backgroundColor: Color(0xFF93C5FD), foregroundColor: Color(0xFF0F172A), padding:EdgeInsets.all(16)), onPressed:guardarMed, child:Text('GUARDAR PARA \${active!=null?active['nombre'].toUpperCase():'USUARIO'}', style:TextStyle(fontWeight:FontWeight.bold)))),
          ]))),
          // chart
          if(meds.isNotEmpty) Card(child: Padding(padding:EdgeInsets.all(12), child: SizedBox(height:180, child: LineChart(LineChartData(
            lineBarsData:[
              LineChartBarData(spots: List.generate(meds.length, (i)=>FlSpot(i.toDouble(), meds.reversed.toList()[i]['sistolica'].toDouble())), color:Colors.redAccent, dotData:FlDotData(show:false)),
              LineChartBarData(spots: List.generate(meds.length, (i)=>FlSpot(i.toDouble(), meds.reversed.toList()[i]['diastolica'].toDouble())), color:Colors.blueAccent, dotData:FlDotData(show:false)),
            ]
          )))))),
          // lista
          ...meds.map((m){
            final cat=categoria(m['sistolica'],m['diastolica']);
            return Card(child: ListTile(leading: Container(width:4, height:40, color:catColor(cat)), title:Text('\${m['sistolica']}/\${m['diastolica']} - \$cat', style:TextStyle(fontWeight:FontWeight.bold)), subtitle:Text('\${m['fecha'].toString().substring(0,16)} \${m['brazo']} \${m['posicion']} \${m['notas']}'), trailing: Text('\${m['pulso']} bpm')));
          }).toList(),
          Row(children:[
            Expanded(child: ElevatedButton(onPressed:(){
              final csv=const ListToCsvConverter().convert([['fecha','sis','dia'], ...meds.map((m)=>[m['fecha'],m['sistolica'],m['diastolica']])]);
              Printing.sharePdf(bytes: csv.codeUnits, filename: 'registros.csv');
            }, child:Text('CSV'))),
            SizedBox(width:8),
            Expanded(child: ElevatedButton(onPressed:generarPDF, child:Text('PDF detallado'))),
          ])
        ])
      )
    );
  }

  String _prom(List<Map> meds, int dias){
    final lim=DateTime.now().subtract(Duration(days:dias));
    final f=meds.where((m)=>DateTime.parse(m['fecha']).isAfter(lim)).toList();
    if(f.isEmpty) return '--';
    final s=(f.map((m)=>m['sistolica'] as int).reduce((a,b)=>a+b)/f.length).round();
    final d=(f.map((m)=>m['diastolica'] as int).reduce((a,b)=>a+b)/f.length).round();
    return '\$s/\$d';
  }
}
