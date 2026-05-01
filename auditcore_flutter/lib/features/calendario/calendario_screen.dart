import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/services/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';


final ganttExpedientesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final resp = await ApiClient.instance.get(
    Endpoints.expedientes,
    queryParameters: {'estado': 'ACTIVO,EN_EJECUCION'},
  );
  final data  = resp.data;
  final lista = data is Map ? (data['results'] as List? ?? []) : (data as List? ?? []);
  return lista.cast<Map<String, dynamic>>();
});

final visitasMesProvider = FutureProvider.autoDispose.family<
    List<Map<String, dynamic>>, DateTime>((ref, mes) async {
  final desde = DateTime(mes.year, mes.month, 1);
  final hasta = DateTime(mes.year, mes.month + 1, 0);
  try {
    final resp = await ApiClient.instance.get(
      Endpoints.visitas,
      queryParameters: {
        'desde': '${desde.year}-${desde.month.toString().padLeft(2,'0')}-01',
        'hasta': '${hasta.year}-${hasta.month.toString().padLeft(2,'0')}-${hasta.day.toString().padLeft(2,'0')}',
      },
    );
    final data  = resp.data;
    final lista = data is Map ? (data['results'] as List? ?? []) : (data as List? ?? []);
    return lista.cast<Map<String, dynamic>>();
  } catch (_) { return []; }
});


class CalendarioScreen extends ConsumerStatefulWidget {
  const CalendarioScreen({super.key});
  @override
  ConsumerState<CalendarioScreen> createState() => _CalendarioScreenState();
}

class _CalendarioScreenState extends ConsumerState<CalendarioScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _mesNotifier = ValueNotifier<DateTime>(
      DateTime(DateTime.now().year, DateTime.now().month));

  @override
  void initState() { super.initState(); _tabs = TabController(length: 2, vsync: this); }
  @override
  void dispose() { _tabs.dispose(); _mesNotifier.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final usuario   = authState.valueOrNull;
    return AppShell(
      rutaActual:    '/calendario',
      rolUsuario:    usuario?.rol ?? '',
      nombreUsuario: usuario?.nombreCompleto ?? '',
      titulo:        'Plan de trabajo',
      subtitulo:     'Cronograma y visitas',
      showBottomNav: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.add_circle_outline, size: 20),
          tooltip: 'Nueva visita',
          onPressed: () => _abrirFormVisita(context),
          style: IconButton.styleFrom(foregroundColor: AppColors.textSecondary),
        ),
        const SizedBox(width: 8),
      ],
      child: Column(children: [
        Container(
          color: AppColors.white,
          child: TabBar(controller: _tabs, tabs: const [
            Tab(text: 'Diagrama de Gantt'),
            Tab(text: 'Visitas agendadas'),
          ]),
        ),
        Expanded(child: TabBarView(controller: _tabs, children: [
          _GanttView(),
          _VisitasView(mesNotifier: _mesNotifier),
        ])),
      ]),
    );
  }

  void _abrirFormVisita(BuildContext context) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _VisitaForm(
        onGuardado: () => ref.invalidate(visitasMesProvider(_mesNotifier.value)),
      ),
    );
  }
}


class _GanttView extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(ganttExpedientesProvider);
    return async.when(
      loading: () => const Center(child: SizedBox(width:24,height:24,child:CircularProgressIndicator(strokeWidth:2))),
      error: (e,_) => EmptyState(titulo:'Error',subtitulo:e.toString(),icono:Icons.error_outline,
          labelBoton:'Reintentar',onBoton:()=>ref.invalidate(ganttExpedientesProvider)),
      data: (exps) => exps.isEmpty
          ? const EmptyState(titulo:'Sin expedientes activos',
              subtitulo:'El Gantt mostrará el plan de trabajo de expedientes activos.',
              icono:Icons.timeline_outlined)
          : _GanttDiagram(expedientes: exps),
    );
  }
}

class _GanttDiagram extends StatefulWidget {
  final List<Map<String,dynamic>> expedientes;
  const _GanttDiagram({required this.expedientes});
  @override State<_GanttDiagram> createState() => _GanttDiagramState();
}

class _GanttDiagramState extends State<_GanttDiagram> {
  static const double rowH=44, labelW=165, dayW=26, headerH=50;
  late DateTime _start; late DateTime _end; late int _days;
  final _hScroll = ScrollController();

  static const _paleta = [
    Color(0xFF3B82F6),Color(0xFF059669),Color(0xFF7C3AED),
    Color(0xFFD97706),Color(0xFFDC2626),Color(0xFF0891B2),
    Color(0xFF65A30D),Color(0xFFDB2777),
  ];

  @override void initState() { super.initState(); _calcRango(); }
  @override void didUpdateWidget(_GanttDiagram o) { super.didUpdateWidget(o); _calcRango(); }
  @override void dispose() { _hScroll.dispose(); super.dispose(); }

  void _calcRango() {
    final hoy = DateTime.now();
    var s = hoy.subtract(const Duration(days:7));
    var e = hoy.add(const Duration(days:90));
    for (final x in widget.expedientes) {
      final a = _pd(x['fecha_apertura'] as String?);
      final b = _pd(x['fecha_estimada_cierre'] as String?);
      if (a!=null && a.isBefore(s)) s=a;
      if (b!=null && b.isAfter(e)) e=b;
    }
    if (e.difference(s).inDays < 60) e = s.add(const Duration(days:60));
    _start=s; _end=e; _days=e.difference(s).inDays+1;
  }

  DateTime? _pd(String? s) {
    if (s==null||s.isEmpty) return null;
    try { return DateTime.parse(s.length>=10?s.substring(0,10):s); } catch(_){return null;}
  }

  @override
  Widget build(BuildContext context) {
    final hoy = DateTime.now();
    final hoyOff = hoy.difference(_start).inDays;
    final totalW = _days * dayW.toDouble();
    return Column(children: [

      Container(color:AppColors.white,
        padding:const EdgeInsets.symmetric(horizontal:12,vertical:8),
        child: Wrap(spacing:12,runSpacing:6,
          children: widget.expedientes.asMap().entries.map((e){
            final c=_paleta[e.key%_paleta.length];
            final pct=(e.value['porcentaje_avance'] as num? ?? 0).round();
            return Row(mainAxisSize:MainAxisSize.min,children:[
              Container(width:10,height:10,decoration:BoxDecoration(color:c,borderRadius:BorderRadius.circular(2))),
              const SizedBox(width:5),
              Text('${e.value['numero_expediente']??'—'}  $pct%',
                  style:const TextStyle(fontSize:10,color:AppColors.textSecondary)),
            ]);
          }).toList(),
        ),
      ),
      const Divider(height:1),
      Expanded(child:SingleChildScrollView(child:SizedBox(
        height: headerH + widget.expedientes.length * rowH + 16,
        child: Row(crossAxisAlignment:CrossAxisAlignment.start,children:[

          SizedBox(width:labelW,child:Column(children:[
            SizedBox(height:headerH),
            ...widget.expedientes.asMap().entries.map((e){
              final c=_paleta[e.key%_paleta.length];
              return SizedBox(height:rowH,child:Row(children:[
                Container(width:3,height:rowH*0.6,color:c,
                    margin:const EdgeInsets.only(left:8,right:8)),
                Expanded(child:Column(mainAxisAlignment:MainAxisAlignment.center,
                    crossAxisAlignment:CrossAxisAlignment.start,children:[
                  Text(e.value['numero_expediente'] as String? ?? '—',
                      style:const TextStyle(fontSize:11,fontWeight:FontWeight.w600,
                          color:AppColors.textPrimary),overflow:TextOverflow.ellipsis),
                  Text(e.value['cliente_nombre'] as String? ?? '—',
                      style:const TextStyle(fontSize:10,color:AppColors.textSecondary),
                      overflow:TextOverflow.ellipsis),
                ])),
              ]));
            }),
          ])),

          Expanded(child:SingleChildScrollView(
            controller:_hScroll,scrollDirection:Axis.horizontal,
            child:SizedBox(width:totalW,
              child:CustomPaint(painter:_GanttPainter(
                expedientes:widget.expedientes,rangeStart:_start,
                totalDays:_days,hoyOffset:hoyOff,
                rowH:rowH,dayW:dayW,headerH:headerH,paleta:_paleta,
              )),
            ),
          )),
        ]),
      ))),
    ]);
  }
}

class _GanttPainter extends CustomPainter {
  final List<Map<String,dynamic>> expedientes;
  final DateTime rangeStart;
  final int totalDays,hoyOffset;
  final double rowH,dayW,headerH;
  final List<Color> paleta;
  const _GanttPainter({required this.expedientes,required this.rangeStart,
    required this.totalDays,required this.hoyOffset,required this.rowH,
    required this.dayW,required this.headerH,required this.paleta});

  DateTime? _pd(String? s){
    if(s==null||s.isEmpty)return null;
    try{return DateTime.parse(s.length>=10?s.substring(0,10):s);}catch(_){return null;}
  }
  String _mes(int m)=>['','Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'][m];

  @override
  void paint(Canvas canvas,Size size){
    final tp=TextPainter(textDirection:TextDirection.ltr);

    for(int i=0;i<expedientes.length;i++){
      final y=headerH+i*rowH;
      canvas.drawRect(Rect.fromLTWH(0,y,size.width,rowH),
        Paint()..color=i.isOdd?const Color(0xFFF8FAFC):Colors.white);
    }

    DateTime cur=rangeStart; String? lastM;
    for(int d=0;d<totalDays;d++){
      final x=d*dayW;
      final m='${_mes(cur.month)} ${cur.year}';
      if(m!=lastM){
        lastM=m;
        canvas.drawLine(Offset(x,0),Offset(x,size.height),
          Paint()..color=AppColors.border..strokeWidth=1.0);
        tp.text=TextSpan(text:m,style:const TextStyle(fontSize:9,
            color:AppColors.textSecondary,fontWeight:FontWeight.w600));
        tp.layout(maxWidth:dayW*28); tp.paint(canvas,Offset(x+3,5));
      } else {
        canvas.drawLine(Offset(x,headerH*0.45),Offset(x,size.height),
          Paint()..color=AppColors.border.withOpacity(0.5)..strokeWidth=0.4);
      }
      if(cur.day==1||cur.day%7==0){
        tp.text=TextSpan(text:'${cur.day}',style:const TextStyle(fontSize:8.5,color:AppColors.textTertiary));
        tp.layout(); tp.paint(canvas,Offset(x+2,headerH-15));
      }
      cur=cur.add(const Duration(days:1));
    }

    if(hoyOffset>=0&&hoyOffset<totalDays){
      final x=hoyOffset*dayW+dayW/2;
      canvas.drawLine(Offset(x,headerH*0.35),Offset(x,size.height),
        Paint()..color=AppColors.danger.withOpacity(0.75)..strokeWidth=1.5);
      tp.text=const TextSpan(text:'HOY',style:TextStyle(fontSize:8,
          color:AppColors.danger,fontWeight:FontWeight.w700));
      tp.layout(); tp.paint(canvas,Offset(x-tp.width/2,26));
    }

    for(int i=0;i<expedientes.length;i++){
      final exp=expedientes[i]; final color=paleta[i%paleta.length];
      final y=headerH+i*rowH;
      final s=_pd(exp['fecha_apertura'] as String?); if(s==null) continue;
      final e=_pd(exp['fecha_estimada_cierre'] as String?)??s.add(const Duration(days:30));
      final so=s.difference(rangeStart).inDays;
      final eo=e.difference(rangeStart).inDays;
      final bx=max(0,so)*dayW; final bw=max(1.0,(eo-max(0,so))*dayW);
      final by=y+rowH*0.2; final bh=rowH*0.55;

      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(bx+1,by+2,bw,bh),const Radius.circular(4)),
        Paint()..color=color.withOpacity(0.15)..maskFilter=const MaskFilter.blur(BlurStyle.normal,3));

      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(bx,by,bw,bh),const Radius.circular(4)),
        Paint()..color=color.withOpacity(0.85));

      final pct=(exp['porcentaje_avance'] as num? ?? 0)/100.0;
      if(pct>0) canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(bx,by,bw*pct,bh),const Radius.circular(4)),
        Paint()..color=Colors.white.withOpacity(0.3));

      if(bw>45){
        tp.text=TextSpan(text:exp['numero_expediente'] as String? ?? '',
            style:const TextStyle(fontSize:9,color:Colors.white,fontWeight:FontWeight.w600));
        tp.layout(maxWidth:bw-6); tp.paint(canvas,Offset(bx+4,by+(bh-tp.height)/2));
      }

      final fases=exp['fases'] as List? ?? [];
      for(int f=0;f<fases.length&&f<4;f++){
        final fase=fases[f] as Map<String,dynamic>;
        final fi=_pd(fase['fecha_inicio'] as String?); if(fi==null) continue;
        final ff=_pd(fase['fecha_fin'] as String?)??fi.add(const Duration(days:7));
        final fso=fi.difference(rangeStart).inDays;
        final feo=ff.difference(rangeStart).inDays;
        final fbx=max(0,fso)*dayW; final fbw=max(1.0,(feo-max(0,fso))*dayW);
        canvas.drawRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(fbx,y+rowH*0.78,fbw,rowH*0.11),const Radius.circular(2)),
          Paint()..color=color.withOpacity(0.9-f*0.2));
      }
    }
  }
  @override bool shouldRepaint(_GanttPainter o)=>o.expedientes!=expedientes;
}


class _VisitasView extends ConsumerStatefulWidget {
  final ValueNotifier<DateTime> mesNotifier;
  const _VisitasView({required this.mesNotifier});
  @override ConsumerState<_VisitasView> createState() => _VisitasViewState();
}

class _VisitasViewState extends ConsumerState<_VisitasView> {
  late DateTime _mes;
  @override void initState(){super.initState();_mes=widget.mesNotifier.value;widget.mesNotifier.addListener(_onC);}
  void _onC()=>setState(()=>_mes=widget.mesNotifier.value);
  @override void dispose(){widget.mesNotifier.removeListener(_onC);super.dispose();}

  static const _meses=['','Enero','Febrero','Marzo','Abril','Mayo','Junio',
    'Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'];

  @override
  Widget build(BuildContext context){
    final async=ref.watch(visitasMesProvider(_mes));
    return Column(children:[
      Container(color:AppColors.white,padding:const EdgeInsets.symmetric(horizontal:8,vertical:6),
        child:Row(children:[
          IconButton(icon:const Icon(Icons.chevron_left),
            onPressed:(){setState(()=>_mes=DateTime(_mes.year,_mes.month-1));widget.mesNotifier.value=_mes;},
            style:IconButton.styleFrom(foregroundColor:AppColors.textSecondary)),
          Expanded(child:Center(child:Text('${_meses[_mes.month]} ${_mes.year}',
              style:const TextStyle(fontSize:14,fontWeight:FontWeight.w600)))),
          IconButton(icon:const Icon(Icons.chevron_right),
            onPressed:(){setState(()=>_mes=DateTime(_mes.year,_mes.month+1));widget.mesNotifier.value=_mes;},
            style:IconButton.styleFrom(foregroundColor:AppColors.textSecondary)),
        ]),
      ),
      const Divider(height:1),
      Expanded(child:async.when(
        loading:()=>const Center(child:SizedBox(width:24,height:24,child:CircularProgressIndicator(strokeWidth:2))),
        error:(e,_)=>EmptyState(titulo:'Error',subtitulo:e.toString(),icono:Icons.error_outline,
            labelBoton:'Reintentar',onBoton:()=>ref.invalidate(visitasMesProvider(_mes))),
        data:(v)=>v.isEmpty
            ? const EmptyState(titulo:'Sin visitas este mes',
                subtitulo:'Usa el botón + para agendar una visita.',
                icono:Icons.calendar_today_outlined)
            : ListView.separated(padding:const EdgeInsets.all(14),itemCount:v.length,
                separatorBuilder:(_,__)=>const SizedBox(height:8),
                itemBuilder:(_,i)=>_VisitaCard(visita:v[i],
                    onActualizar:()=>ref.invalidate(visitasMesProvider(_mes)))),
      )),
    ]);
  }
}

class _VisitaCard extends StatelessWidget {
  final Map<String,dynamic> visita; final VoidCallback onActualizar;
  const _VisitaCard({required this.visita,required this.onActualizar});

  Color _c(String e)=>switch(e){
    'PROGRAMADA'=>const Color(0xFF3B82F6),'CONFIRMADA'=>const Color(0xFF059669),
    'REALIZADA'=>const Color(0xFF94A3B8),'REPROGRAMADA'=>const Color(0xFFD97706),
    'CANCELADA'=>const Color(0xFFEF4444),_=>const Color(0xFF94A3B8)};

  String _hora(String? iso){if(iso==null)return '';
    try{final dt=DateTime.parse(iso).toLocal();return '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';}catch(_){return '';}}
  String _fecha(String? iso){if(iso==null)return '';
    try{final dt=DateTime.parse(iso).toLocal();return '${dt.day}/${dt.month}/${dt.year}';}catch(_){return '';}}

  @override
  Widget build(BuildContext context){
    final estado=visita['estado'] as String? ?? ''; final c=_c(estado);
    return Card(child:Padding(padding:const EdgeInsets.all(12),
      child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Container(width:4,height:60,decoration:BoxDecoration(color:c,borderRadius:BorderRadius.circular(2))),
        const SizedBox(width:12),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[
            Expanded(child:Text(visita['titulo'] as String? ?? '—',
                style:const TextStyle(fontSize:13,fontWeight:FontWeight.w600,color:AppColors.textPrimary))),
            Container(padding:const EdgeInsets.symmetric(horizontal:6,vertical:2),
              decoration:BoxDecoration(color:c.withOpacity(0.12),borderRadius:BorderRadius.circular(10)),
              child:Text(estado,style:TextStyle(fontSize:10,color:c,fontWeight:FontWeight.w500))),
          ]),
          const SizedBox(height:4),
          Text('${_fecha(visita['fecha_inicio'] as String?)}  ${_hora(visita['fecha_inicio'] as String?)} – ${_hora(visita['fecha_fin'] as String?)}',
              style:const TextStyle(fontSize:11,color:AppColors.textTertiary)),
          if((visita['expediente_numero']??'').isNotEmpty)
            Text(visita['expediente_numero'] as String,
                style:const TextStyle(fontSize:11,color:AppColors.textTertiary)),
          if((visita['lugar'] as String? ?? '').isNotEmpty)
            Text(visita['lugar'] as String,
                style:const TextStyle(fontSize:11,color:AppColors.textTertiary),
                overflow:TextOverflow.ellipsis),
        ])),
      ])));
  }
}


class _VisitaForm extends ConsumerStatefulWidget {
  final VoidCallback onGuardado;
  const _VisitaForm({required this.onGuardado});
  @override ConsumerState<_VisitaForm> createState()=>_VisitaFormState();
}

class _VisitaFormState extends ConsumerState<_VisitaForm> {
  final _form=GlobalKey<FormState>();
  final _tituloCtrl=TextEditingController(),_lugarCtrl=TextEditingController(),_descCtrl=TextEditingController();
  String? _expedienteId; String _tipo='CAMPO';
  DateTime _inicio=DateTime.now(); DateTime _fin=DateTime.now().add(const Duration(hours:2));
  bool _guardando=false; String? _error;

  static const _tipos=[('APERTURA','Reunión de apertura'),('CAMPO','Visita en campo'),
    ('DOCUMENTACION','Revisión documentación'),('SEGUIMIENTO','Seguimiento hallazgos'),
    ('CIERRE','Reunión de cierre'),('OTRO','Otro')];

  @override void dispose(){_tituloCtrl.dispose();_lugarCtrl.dispose();_descCtrl.dispose();super.dispose();}

  String _fmt(DateTime dt)=>'${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';

  Future<void> _pickInicio() async {
    final d=await showDatePicker(context:context,initialDate:_inicio,firstDate:DateTime(2020),lastDate:DateTime(2030));
    if(d==null||!mounted)return;
    final t=await showTimePicker(context:context,initialTime:TimeOfDay.fromDateTime(_inicio));
    if(t==null)return;
    setState((){_inicio=DateTime(d.year,d.month,d.day,t.hour,t.minute);if(_fin.isBefore(_inicio))_fin=_inicio.add(const Duration(hours:2));});
  }

  Future<void> _pickFin() async {
    final d=await showDatePicker(context:context,initialDate:_fin,firstDate:_inicio,lastDate:DateTime(2030));
    if(d==null||!mounted)return;
    final t=await showTimePicker(context:context,initialTime:TimeOfDay.fromDateTime(_fin));
    if(t==null)return;
    setState(()=>_fin=DateTime(d.year,d.month,d.day,t.hour,t.minute));
  }

  Future<void> _guardar() async {
    if(!_form.currentState!.validate())return;
    if(_expedienteId==null){setState(()=>_error='Selecciona un expediente.');return;}
    if(_guardando)return;
    setState((){_guardando=true;_error=null;});
    try {
      await ApiClient.instance.post(Endpoints.visitas,data:{
        'expediente':_expedienteId,'tipo':_tipo,'titulo':_tituloCtrl.text.trim(),
        'descripcion':_descCtrl.text.trim(),'fecha_inicio':_inicio.toUtc().toIso8601String(),
        'fecha_fin':_fin.toUtc().toIso8601String(),'lugar':_lugarCtrl.text.trim(),
      });
      widget.onGuardado();
      if(mounted)Navigator.of(context).pop();
    } catch(e){setState(()=>_error=e.toString());}
    finally{if(mounted)setState(()=>_guardando=false);}
  }

  Widget _lbl(String t)=>Padding(padding:const EdgeInsets.only(bottom:5),
    child:Text(t,style:const TextStyle(fontSize:12,fontWeight:FontWeight.w500,color:AppColors.textSecondary)));

  @override
  Widget build(BuildContext context){
    final expAsync=ref.watch(expedientesProvider);
    return Container(
      decoration:const BoxDecoration(color:AppColors.white,borderRadius:BorderRadius.vertical(top:Radius.circular(16))),
      padding:EdgeInsets.fromLTRB(20,20,20,MediaQuery.of(context).viewInsets.bottom+24),
      child:Form(key:_form,child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[
          const Text('Nueva visita',style:TextStyle(fontSize:16,fontWeight:FontWeight.w600,color:AppColors.textPrimary)),
          const Spacer(),
          IconButton(onPressed:()=>Navigator.of(context).pop(),icon:const Icon(Icons.close,size:18),
            style:IconButton.styleFrom(foregroundColor:AppColors.textSecondary)),
        ]),
        const SizedBox(height:16),
        _lbl('Título *'),
        TextFormField(controller:_tituloCtrl,style:const TextStyle(fontSize:13),
          decoration:const InputDecoration(hintText:'Ej: Visita inicial ISO 9001'),
          validator:(v)=>v==null||v.trim().isEmpty?'Requerido':null),
        const SizedBox(height:12),
        _lbl('Expediente *'),
        expAsync.when(
          loading:()=>const LinearProgressIndicator(),
          error:(_,__)=>const Text('Error',style:TextStyle(fontSize:12,color:AppColors.danger)),
          data:(exps)=>DropdownButtonFormField<String>(
            value:_expedienteId,isExpanded:true,
            hint:const Text('Seleccionar',style:TextStyle(fontSize:13)),
            style:const TextStyle(fontSize:13,color:AppColors.textPrimary),
            items:exps.map((e)=>DropdownMenuItem(value:e.id,
              child:Text('${e.numeroExpediente} — ${e.clienteNombre}',overflow:TextOverflow.ellipsis))).toList(),
            onChanged:(v)=>setState(()=>_expedienteId=v),
          ),
        ),
        const SizedBox(height:12),
        _lbl('Tipo'),
        DropdownButtonFormField<String>(value:_tipo,
          style:const TextStyle(fontSize:13,color:AppColors.textPrimary),
          items:_tipos.map((t)=>DropdownMenuItem(value:t.$1,child:Text(t.$2))).toList(),
          onChanged:(v)=>setState(()=>_tipo=v!)),
        const SizedBox(height:12),
        Row(children:[
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            _lbl('Inicio *'),
            GestureDetector(onTap:_pickInicio,child:Container(
              padding:const EdgeInsets.symmetric(horizontal:12,vertical:11),
              decoration:BoxDecoration(border:Border.all(color:AppColors.border),borderRadius:BorderRadius.circular(8)),
              child:Text(_fmt(_inicio),style:const TextStyle(fontSize:12)))),
          ])),
          const SizedBox(width:10),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            _lbl('Fin *'),
            GestureDetector(onTap:_pickFin,child:Container(
              padding:const EdgeInsets.symmetric(horizontal:12,vertical:11),
              decoration:BoxDecoration(border:Border.all(color:AppColors.border),borderRadius:BorderRadius.circular(8)),
              child:Text(_fmt(_fin),style:const TextStyle(fontSize:12)))),
          ])),
        ]),
        const SizedBox(height:12),
        _lbl('Lugar'),
        TextFormField(controller:_lugarCtrl,style:const TextStyle(fontSize:13),
          decoration:const InputDecoration(hintText:'Dirección o nombre de la sede')),
        if(_error!=null)...[
          const SizedBox(height:12),
          Container(padding:const EdgeInsets.all(10),
            decoration:BoxDecoration(color:AppColors.dangerBg,borderRadius:BorderRadius.circular(6)),
            child:Text(_error!,style:const TextStyle(fontSize:12,color:AppColors.danger))),
        ],
        const SizedBox(height:20),
        SizedBox(width:double.infinity,child:ElevatedButton(
          onPressed:_guardando?null:_guardar,
          child:_guardando
              ?const SizedBox(width:16,height:16,child:CircularProgressIndicator(color:Colors.white,strokeWidth:2))
              :const Text('Agendar visita'))),
      ]))),
    );
  }
}
