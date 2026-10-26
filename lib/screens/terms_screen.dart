import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_theme.dart';

/// Versión y fecha de vigencia de cada documento legal. Al publicar una
/// versión nueva de un texto, cambia su versión y su fecha: las cuentas
/// que aceptaron una versión anterior verán el botón "Aceptar" otra vez
/// en Mi negocio.
const String kTerminosVersion = '1.0';
const String kTerminosVigencia = '24/10/2026';
const String kPrivacidadVersion = '1.0';
const String kPrivacidadVigencia = '24/10/2026';

/// Datos que se guardan en la cuenta de Supabase (user_metadata) al
/// aceptar: la versión y fecha de cada documento (Términos y Política de
/// Privacidad, por separado) y la autorización expresa de la
/// transferencia internacional de datos (también por separado). Todo en
/// UTC. Se usa al crear la cuenta (`signUp(data: ...)`) y al aceptar
/// desde una cuenta existente (`updateUser`).
Map<String, dynamic> metadatosAceptacion() {
  final ahora = DateTime.now().toUtc().toIso8601String();
  return {
    'terminos_version': kTerminosVersion,
    'terminos_aceptados_en': ahora,
    'privacidad_version': kPrivacidadVersion,
    'privacidad_aceptada_en': ahora,
    'transferencia_internacional_autorizada_en': ahora,
  };
}

/// Lo que la cuenta actual tiene registrado sobre los documentos legales.
class AceptacionTerminos {
  final String? version; // versión aceptada de los Términos
  final String? versionPrivacidad; // versión aceptada de la Política
  final DateTime? fecha; // cuándo aceptó los Términos

  const AceptacionTerminos(this.version, this.versionPrivacidad, this.fecha);

  factory AceptacionTerminos.delUsuarioActual() {
    final meta = Supabase.instance.client.auth.currentUser?.userMetadata;
    final fecha = DateTime.tryParse(
      (meta?['terminos_aceptados_en'] as String?) ?? '',
    )?.toLocal();
    return AceptacionTerminos(
      meta?['terminos_version'] as String?,
      meta?['privacidad_version'] as String?,
      fecha,
    );
  }

  /// true si ya aceptó la versión vigente de AMBOS documentos.
  bool get vigente =>
      version == kTerminosVersion && versionPrivacidad == kPrivacidadVersion;

  /// dd/mm/aaaa, o null si no hay fecha registrada.
  String? get fechaTexto {
    final f = fecha;
    if (f == null) return null;
    final dia = f.day.toString().padLeft(2, '0');
    final mes = f.month.toString().padLeft(2, '0');
    return '$dia/$mes/${f.year}';
  }
}

/// Cómo se abre la pantalla.
enum ModoTerminos {
  /// Al crear la cuenta: muestra "Rechazar" y "Aceptar". Devuelve true
  /// solo si se acepta; rechazar o volver atrás devuelve false/null.
  decision,

  /// Solo lectura (por ejemplo, desde Mi negocio). Si la cuenta no ha
  /// aceptado las versiones vigentes, ofrece el botón "Aceptar".
  lectura,
}

/// Muestra los Términos y Condiciones y la Política de Privacidad en dos
/// pestañas. La aceptación cubre ambos documentos, pero se registra la
/// versión de cada uno y, aparte, la autorización de la transferencia
/// internacional de datos (casilla propia).
class TermsScreen extends StatefulWidget {
  final ModoTerminos modo;

  const TermsScreen({super.key, this.modo = ModoTerminos.lectura});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  late AceptacionTerminos _aceptacion = widget.modo == ModoTerminos.lectura
      ? AceptacionTerminos.delUsuarioActual()
      : const AceptacionTerminos(null, null, null);
  bool _autorizaTransferencia = false;
  bool _guardando = false;

  /// Cuenta que ya existía: registra la aceptación en su perfil.
  Future<void> _aceptarCuentaExistente() async {
    setState(() => _guardando = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: metadatosAceptacion()),
      );
      if (!mounted) return;
      setState(() {
        _aceptacion = AceptacionTerminos.delUsuarioActual();
        _guardando = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registramos tu aceptación.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo registrar la aceptación. Intenta de nuevo.'),
        ),
      );
    }
  }

  /// Texto con **negritas** simples.
  Widget _textoRico(String texto, TextStyle? base) {
    final partes = texto.split('**');
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          for (var i = 0; i < partes.length; i++)
            TextSpan(
              text: partes[i],
              style: i.isOdd ? const TextStyle(fontWeight: FontWeight.bold) : null,
            ),
        ],
      ),
    );
  }

  /// Convierte el texto en markdown simple (## títulos, - viñetas,
  /// párrafos) en widgets.
  List<Widget> _contenido(ThemeData tema, String markdown) {
    final cuerpo = tema.textTheme.bodyMedium?.copyWith(height: 1.4);
    final widgets = <Widget>[];

    for (final linea in markdown.split('\n')) {
      final texto = linea.trim();
      if (texto.isEmpty) continue;

      if (texto.startsWith('## ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 22, bottom: 8),
          child: Text(
            texto.substring(3),
            style: tema.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ));
      } else if (texto.startsWith('- ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: cuerpo),
              Expanded(child: _textoRico(texto.substring(2), cuerpo)),
            ],
          ),
        ));
      } else {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _textoRico(texto, cuerpo),
        ));
      }
    }
    return widgets;
  }

  Widget _aviso(ThemeData tema, String mensaje) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tema.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        mensaje,
        style: tema.textTheme.bodyMedium?.copyWith(
          color: tema.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  /// Aviso de la parte superior según el modo y el estado de la cuenta.
  Widget? _avisoSuperior(ThemeData tema) {
    if (widget.modo == ModoTerminos.decision) {
      return _aviso(
        tema,
        'Para crear tu cuenta debes aceptar los Términos y Condiciones y la '
        'Política de Privacidad, y autorizar la transferencia de datos. '
        'Si los rechazas, la cuenta no se creará.',
      );
    }
    if (_aceptacion.fecha == null) return null;
    if (_aceptacion.vigente) {
      return _aviso(
        tema,
        'Aceptaste los Términos (versión ${_aceptacion.version}) y la Política '
        'de Privacidad (versión ${_aceptacion.versionPrivacidad}) el '
        '${_aceptacion.fechaTexto}.',
      );
    }
    return _aviso(
      tema,
      'Hay versiones nuevas de estos documentos pendientes de aceptar.',
    );
  }

  Widget _documento(
    ThemeData tema, {
    required String titulo,
    required String version,
    required String vigencia,
    required String markdown,
  }) {
    final aviso = _avisoSuperior(tema);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text(titulo, style: tema.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          'Green Garden · Green Garden Solutions',
          style: tema.textTheme.bodyMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Versión $version · Última actualización: $vigencia · '
          'Fecha de vigencia: $vigencia',
          style: tema.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        ?aviso,
        ..._contenido(tema, markdown),
      ],
    );
  }

  Widget? _barraInferior(ThemeData tema) {
    final decision = widget.modo == ModoTerminos.decision;
    final pendiente = decision || !_aceptacion.vigente;
    if (!pendiente) return null;

    final puedeAceptar = _autorizaTransferencia && !_guardando;

    final Widget botones;
    if (decision) {
      botones = Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Rechazar'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: puedeAceptar ? () => Navigator.pop(context, true) : null,
              child: const Text('Aceptar'),
            ),
          ),
        ],
      );
    } else {
      botones = SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: puedeAceptar ? _aceptarCuentaExistente : null,
          child: _guardando
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Aceptar Términos y Política de Privacidad'),
        ),
      );
    }

    return Material(
      elevation: 8,
      color: tema.colorScheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Autorización separada de la transferencia internacional
              // (sección 7 de la Política de Privacidad).
              CheckboxListTile(
                value: _autorizaTransferencia,
                onChanged: _guardando
                    ? null
                    : (v) => setState(() => _autorizaTransferencia = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  'Autorizo expresamente que los datos de mi cuenta se '
                  'almacenen y procesen en servidores ubicados en Estados '
                  'Unidos (región East US, North Virginia), necesarios para '
                  'prestar el Servicio. Ver la sección 7 de la Política de '
                  'Privacidad.',
                  style: tema.textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 4),
              botones,
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final colorAppBar = tema.appBarTheme.foregroundColor;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Legal'),
          bottom: TabBar(
            indicatorColor: AppColors.limeGreen,
            indicatorWeight: 3,
            // Mismo criterio que en Inventario: ambos colores salen del
            // foregroundColor del AppBar para que contrasten en los dos
            // temas.
            labelColor: colorAppBar,
            unselectedLabelColor: colorAppBar?.withValues(alpha: 0.65),
            tabs: const [
              Tab(text: 'Términos'),
              Tab(text: 'Privacidad'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _documento(
              tema,
              titulo: 'Términos y Condiciones de Uso y Servicio',
              version: kTerminosVersion,
              vigencia: kTerminosVigencia,
              markdown: _kTerminosMarkdown,
            ),
            _documento(
              tema,
              titulo: 'Política de Privacidad',
              version: kPrivacidadVersion,
              vigencia: kPrivacidadVigencia,
              markdown: _kPrivacidadMarkdown,
            ),
          ],
        ),
        bottomNavigationBar: _barraInferior(tema),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// TEXTO DE LOS DOCUMENTOS LEGALES
//
// Son los mismos contenidos de los documentos "Términos y Condiciones de
// Uso y Servicio" y "Política de Privacidad". Formato: "## " = título de sección, "- " = viñeta,
// **texto** = negrita; cada línea sin marca es un párrafo.
// Para actualizar uno: pega el texto nuevo aquí y sube su versión y
// vigencia (constantes del inicio del archivo).
// ---------------------------------------------------------------------
const String _kTerminosMarkdown = r'''
Lea con atención este documento antes de crear una cuenta o utilizar la aplicación. Al aceptar estos Términos y Condiciones, el Usuario declara haberlos leído, comprendido y aceptado en su totalidad.

## 1. Identificación del Proveedor

Estos Términos y Condiciones (los “Términos”) regulan el acceso y el uso de la aplicación móvil Green Garden (la “Aplicación”) y de los servicios asociados a ella (el “Servicio”), que son ofrecidos por:

- **Proveedor:** Quevin Batista, persona natural, quien opera bajo el nombre comercial **Green Garden Solutions** (en adelante, el “Proveedor”).
- **Domicilio para notificaciones:** el correo electrónico indicado a continuación. Los datos de identificación fiscal del Proveedor se consignan en la Propuesta de Servicio y en los comprobantes que emita.
- **Correo electrónico de contacto:** quevinyahir28@gmail.com.

## 2. Definiciones

Para los efectos de estos Términos, las siguientes expresiones tendrán el significado que se indica:

- **Aplicación:** el software Green Garden, en sus versiones móvil y de respaldo en la nube, incluidas sus actualizaciones.
- **Servicio:** el acceso a la Aplicación, su instalación y configuración inicial, el alojamiento de la información y el soporte técnico descritos en estos Términos y en la Propuesta de Servicio.
- **Usuario:** la persona natural que accede a la Aplicación mediante una Cuenta.
- **Cliente:** la persona natural o jurídica que contrata el Servicio con el Proveedor. Puede coincidir con el Usuario.
- **Cuenta:** el registro individual, protegido por credenciales, mediante el cual el Usuario accede a la Aplicación.
- **Clientes Finales:** las personas cuyos datos el Cliente registra en la Aplicación en el curso de su actividad comercial.
- **Contenido del Cliente:** toda la información, datos, imágenes, logotipos y registros que el Cliente o el Usuario ingresan en la Aplicación.
- **Propuesta de Servicio:** el documento o comunicación escrita, incluido el correo electrónico, en que el Proveedor y el Cliente acuerdan el alcance, los precios y las condiciones particulares del Servicio.
- **Datos Personales, Responsable del Tratamiento y Custodio de la Base de Datos:** tienen el significado que les atribuyen la Ley 81 de 2019 y su reglamento.
- **Política de Privacidad:** el documento independiente que describe qué datos personales trata la Aplicación, con qué finalidad y cómo pueden ejercerse los derechos de sus titulares.

## 3. Aceptación, capacidad y valor jurídico

3.1. El acceso o uso de la Aplicación, así como la aceptación expresa al crear la Cuenta, implican la aceptación de estos Términos y el conocimiento de la Política de Privacidad. El consentimiento para los tratamientos de datos personales que lo requieran se solicita y registra de forma específica, conforme a esa Política.

3.2. El Usuario declara ser mayor de edad y tener capacidad legal para contratar. Si actúa en nombre de una empresa o negocio, declara contar con las facultades necesarias para obligarlo.

3.3. El Proveedor conservará un registro electrónico de la aceptación (fecha, hora, versión de cada documento aceptado, es decir, de estos Términos y de la Política de Privacidad, e identificador de la Cuenta) como constancia. Las partes reconocen que la aceptación por medios electrónicos es válida conforme a la legislación panameña sobre documentos y comercio electrónico (Ley 51 de 2008, modificada por la Ley 82 de 2012) y al principio de libertad de forma de los contratos mercantiles.

3.4. Estos Términos, la Política de Privacidad y la Propuesta de Servicio constituyen el acuerdo completo entre las partes. En caso de contradicción, la Propuesta de Servicio prevalecerá en lo relativo a precios, alcance y plazos particulares.

## 4. Descripción del Servicio

4.1. Green Garden es una herramienta de gestión para negocios de servicios de jardinería y mantenimiento de áreas verdes. Según la versión contratada, incluye:

- Registro de clientes, agenda de trabajos, servicios recurrentes y seguimiento del estado de cada trabajo (pendiente, realizado y pagado).
- Catálogo de servicios y tarifas, y configuración del consumo de insumos por servicio.
- Control de inventario de herramientas e insumos, con alertas de stock bajo y descuento automático de insumos al marcar un trabajo como realizado.
- Registro de ingresos y gastos, y gráficas de apoyo financiero.
- Cotizaciones y generación de facturas de servicio en formato PDF.
- Notificaciones y recordatorios programados en el dispositivo.
- Modo sin conexión con sincronización posterior.
- Personalización de marca (logotipo y color) y acceso mediante huella o rostro.

4.2. El Proveedor podrá modificar, agregar o retirar funciones de la Aplicación para mejorarla, corregir errores o cumplir requisitos legales o técnicos, procurando no afectar de manera sustancial el Servicio contratado.

## 5. Cuenta, credenciales y acceso biométrico

5.1. El Usuario debe proporcionar información veraz y mantenerla actualizada.

5.2. El Usuario es responsable de custodiar su correo electrónico y su contraseña, y de toda actividad realizada desde su Cuenta. Debe notificar sin demora al Proveedor cualquier acceso no autorizado del que tenga conocimiento.

5.3. La recuperación de contraseña se realiza mediante un código de verificación enviado al correo electrónico registrado. El Usuario es responsable de mantener el control de ese correo.

5.4. El acceso con huella o rostro es una función opcional que el propio sistema operativo del dispositivo gestiona. La Aplicación no recibe, almacena ni transmite datos biométricos. Se trata de un bloqueo de la interfaz de la Aplicación y no constituye un mecanismo de cifrado de la información almacenada en el dispositivo.

5.5. El Proveedor podrá suspender temporalmente una Cuenta cuando existan indicios razonables de uso no autorizado, riesgo para la seguridad o incumplimiento de estos Términos, y lo comunicará al Cliente tan pronto sea posible.

## 6. Instalación, precios, pagos y soporte

6.1. **Instalación y configuración inicial.** Consiste en la puesta en marcha de la Cuenta, la configuración básica del negocio del Cliente (datos del negocio, marca, catálogo inicial) y la orientación inicial de uso, conforme al alcance indicado en la Propuesta de Servicio. Se cobra por una sola vez.

6.2. **Mensualidad de soporte.** Cubre la atención de consultas de uso, la corrección de fallas de la Aplicación, el mantenimiento básico y las actualizaciones de la Aplicación durante el período pagado. No cubre el desarrollo de funciones nuevas a medida, la capacitación adicional, ni la reparación de daños causados por uso indebido, por modificaciones no autorizadas o por fallas de equipos, redes o servicios de terceros.

6.3. **Atención.** El soporte se presta por los canales y en el horario indicados en la Propuesta de Servicio, en días hábiles. El Proveedor se compromete a dar una primera respuesta dentro de un plazo objetivo de dos (2) días hábiles. Este plazo es orientativo y no constituye una garantía de resolución.

6.4. **Precios.** Los montos, la moneda y la periodicidad de pago se establecen en la Propuesta de Servicio e incluyen o excluyen los impuestos aplicables según allí se indique. Cualquier cambio de precio de la mensualidad será comunicado con al menos treinta (30) días de anticipación y no se aplicará a períodos ya pagados.

6.5. **Comprobantes.** El Proveedor emitirá los comprobantes fiscales correspondientes a sus cobros conforme a la normativa tributaria panameña vigente.

6.6. **Mora y suspensión.** Si una mensualidad no se paga a tiempo, el Proveedor notificará al Cliente por escrito. Transcurridos quince (15) días calendario desde esa notificación sin que se regularice el pago, el Proveedor podrá suspender el acceso al Servicio. Durante la suspensión, los datos del Cliente se conservarán por el plazo previsto en la cláusula 20.4 para que el Cliente pueda exportarlos o reactivar el Servicio.

6.7. **Reembolsos.** Si el Servicio no pudo prestarse por causa imputable al Proveedor, el Cliente tendrá derecho a la devolución proporcional de la mensualidad correspondiente al período no prestado. Si la instalación inicial no se completa por causa imputable al Proveedor, se devolverá la parte del precio que corresponda a la labor no ejecutada. La instalación efectivamente realizada no es reembolsable. Nada de lo dispuesto en esta cláusula limita los derechos que la ley reconozca irrenunciablemente al consumidor.

## 7. Uso permitido y prohibiciones

7.1. El Usuario se compromete a utilizar la Aplicación únicamente para fines lícitos y para la gestión de su propio negocio.

7.2. Queda prohibido:

- Intentar acceder a Cuentas, datos o sistemas de otros usuarios, o eludir las medidas de seguridad de la Aplicación.
- Copiar, descompilar, realizar ingeniería inversa, modificar, sublicenciar, revender o distribuir la Aplicación o parte de ella sin autorización escrita del Proveedor.
- Introducir virus, código malicioso o cualquier elemento que dañe o sobrecargue el Servicio.
- Registrar datos de terceros sin contar con una base legal o con su consentimiento cuando este sea exigible.
- Utilizar el Servicio para actividades ilícitas, fraudulentas o contrarias a la moral y al orden público.

7.3. El incumplimiento grave de esta cláusula faculta al Proveedor a suspender o terminar la Cuenta conforme a la cláusula 20.

## 8. Tratamiento de datos: roles y responsabilidades

8.1. **Titularidad.** El Contenido del Cliente pertenece al Cliente. El Proveedor no adquiere derecho de propiedad sobre él. Los datos de la cuenta del Usuario (correo, credenciales, datos del negocio y registro de aceptación) los trata el Proveedor como responsable del tratamiento, conforme a la Política de Privacidad.

8.2. **Responsable del tratamiento.** El Cliente es el Responsable del Tratamiento de los Datos Personales de sus Clientes Finales (nombre, dirección, historial de servicios y cobros, entre otros). Es su responsabilidad contar con una base legal o con el consentimiento informado de dichos titulares, informarles la finalidad del tratamiento y atender sus solicitudes de acceso, rectificación, cancelación, oposición y portabilidad.

8.3. **Custodio de la base de datos.** El Proveedor actúa como Custodio de la Base de Datos por cuenta del Cliente. Conserva y protege la información únicamente para prestar el Servicio y siguiendo las instrucciones del Cliente. No la vende, no la cede a terceros con fines propios ni la utiliza para fines distintos a los de este acuerdo.

8.4. **Medidas de seguridad.** El Proveedor aplica medidas técnicas y organizativas razonables, entre ellas el aislamiento de los datos por Cuenta mediante políticas de seguridad a nivel de base de datos, la comunicación cifrada entre la Aplicación y el servidor, y el acceso restringido a la información. Ningún sistema es absolutamente invulnerable, por lo que el Proveedor no garantiza una seguridad total.

8.5. **Terceros que prestan infraestructura.** Para prestar el Servicio, el Proveedor utiliza proveedores de infraestructura, entre ellos Supabase (alojamiento de la base de datos y autenticación) y un servicio de correo electrónico para el envío de códigos de verificación. Estos proveedores pueden tener sus servidores fuera de la República de Panamá, por lo que el uso del Servicio puede implicar una transferencia internacional de datos, la cual se informa y se regula en la Política de Privacidad. El Proveedor procura que sus proveedores ofrezcan medidas de protección adecuadas.

8.6. **Incidentes de seguridad.** Si el Proveedor detecta una violación de seguridad que afecte los datos del Cliente, se lo notificará de inmediato, indicando la información disponible, los datos afectados y las medidas de contención adoptadas. Conservará un registro del incidente y colaborará para que el Cliente pueda cumplir las notificaciones que la ley le exija. Ese aviso no sustituye las obligaciones legales del Cliente como responsable.

8.7. **Ejercicio de derechos.** Las solicitudes de acceso, rectificación, cancelación, oposición o portabilidad de datos pueden dirigirse al correo indicado en la cláusula 27, y el Proveedor las atenderá dentro de los plazos legales. El Proveedor colaborará con el Cliente para que este pueda responder a las solicitudes de sus Clientes Finales.

8.8. **Política de Privacidad.** El tratamiento de datos personales se describe con mayor detalle en la Política de Privacidad, que forma parte integral de estos Términos.

## 9. Facturas, cotizaciones y finanzas

9.1. Los documentos en PDF que genera la Aplicación (facturas de servicio, cotizaciones y similares) son comprobantes de la prestación de un servicio y **no son facturas fiscales**. No reemplazan la factura electrónica ni los documentos fiscales exigidos por la Dirección General de Ingresos (DGI).

9.2. El Cliente es el único responsable de cumplir sus obligaciones tributarias, entre ellas la emisión de comprobantes fiscales, el cobro y la declaración del ITBMS cuando corresponda, y la conservación de sus registros.

9.3. Las cotizaciones generadas por la Aplicación son propuestas informativas, no constituyen un contrato por sí mismas y están sujetas a la validez y condiciones que el Cliente defina.

9.4. Los cálculos, totales y gráficas financieras de la Aplicación son una ayuda de gestión. No constituyen contabilidad oficial ni asesoría contable, tributaria o legal. El Cliente debe verificarlos y consultar a un profesional cuando sea necesario.

## 10. Registro de cobros

La Aplicación únicamente permite registrar la forma en que un Cliente Final pagó (por ejemplo, Yappy o efectivo). No procesa pagos, no custodia dinero, no actúa como intermediaria financiera y no verifica la autenticidad de las transacciones.

## 11. Notificaciones y recordatorios

Los recordatorios (trabajos agendados, cobros pendientes, stock bajo, entre otros) se generan y programan en el propio dispositivo del Usuario. Su entrega depende de los permisos concedidos, del ahorro de batería, de la configuración del sistema operativo y de las políticas del fabricante del dispositivo. El Proveedor no garantiza que todas las notificaciones se muestren en el momento previsto, por lo que el Usuario no debe depender exclusivamente de ellas para cumplir compromisos.

## 12. Inventario y descuento automático

El descuento automático de insumos se calcula a partir de las cantidades que el propio Usuario configura para cada servicio. El Usuario es responsable de que esa configuración sea correcta y de contrastar periódicamente el inventario registrado con el existente. El Proveedor no responde por diferencias derivadas de configuraciones erróneas, pérdidas, mermas o consumos no registrados.

## 13. Modo sin conexión y sincronización

13.1. La Aplicación permite registrar ciertas operaciones sin conexión a internet, las cuales se almacenan en el dispositivo y se sincronizan cuando la conexión se restablece.

13.2. Los datos que aún no se hayan sincronizado pueden perderse si se cierra la sesión, si la Aplicación se desinstala, si el dispositivo se pierde, se daña o se restablece de fábrica antes de la sincronización. El Usuario debe conectar su dispositivo a internet con regularidad.

13.3. Si se modifican los mismos datos desde varios dispositivos, podrían producirse conflictos de sincronización. En ese caso, prevalecerá la última modificación recibida por el servidor.

## 14. Disponibilidad, mantenimiento y copias de seguridad

14.1. El Servicio se presta según disponibilidad. El Proveedor procurará mantenerlo operativo, pero no garantiza un funcionamiento ininterrumpido ni libre de errores. Podrá realizar tareas de mantenimiento y actualización, procurando avisar con antelación cuando sean programadas.

14.2. El Proveedor no garantiza copias de seguridad adicionales a las que ofrezca su proveedor de infraestructura, salvo que se pacte expresamente en la Propuesta de Servicio. Se recomienda al Cliente exportar y respaldar su información periódicamente.

## 15. Propiedad intelectual

15.1. La Aplicación, su código fuente, diseño, textos, estructura, nombre y marca Green Garden Solutions son propiedad del Proveedor y están protegidos por la legislación de propiedad intelectual. Estos Términos no transfieren al Usuario ningún derecho de propiedad sobre ellos.

15.2. El Proveedor concede al Cliente una licencia limitada, no exclusiva, intransferible y revocable para usar la Aplicación en la gestión de su propio negocio, mientras el Servicio esté vigente.

15.3. El Cliente declara que tiene derecho a utilizar el logotipo y las imágenes que cargue en la Aplicación y otorga al Proveedor la autorización estrictamente necesaria para alojarlos, procesarlos y mostrarlos dentro del Servicio.

## 16. Confidencialidad

Cada parte se obliga a mantener en reserva la información confidencial de la otra a la que acceda con motivo del Servicio, y a no utilizarla para fines distintos a los de este acuerdo. Esta obligación subsiste después de terminado el Servicio y no aplica a la información de dominio público ni a la que deba revelarse por mandato de autoridad competente.

## 17. Exclusión de garantías

La Aplicación es una herramienta de apoyo a la gestión. En la máxima medida permitida por la ley, se ofrece en el estado en que se encuentra, sin garantías de que satisfaga necesidades específicas del Usuario ni de que sus resultados sean exactos o libres de errores. Lo anterior no afecta las garantías o derechos que la ley reconozca de manera irrenunciable.

## 18. Limitación de responsabilidad

18.1. En la máxima medida permitida por la ley, el Proveedor no será responsable por daños indirectos, lucro cesante, pérdida de oportunidades de negocio, pérdida de datos causada por circunstancias ajenas a su control, ni por decisiones comerciales, fiscales o contables adoptadas con base en la información de la Aplicación.

18.2. La responsabilidad total del Proveedor frente al Cliente por cualquier causa se limitará al monto efectivamente pagado por el Cliente por el Servicio durante los doce (12) meses anteriores al hecho que originó el reclamo.

18.3. Estas limitaciones no se aplican en caso de dolo o culpa grave del Proveedor, ni cuando la ley prohíba limitar la responsabilidad.

## 19. Indemnidad

En la medida permitida por la ley, el Cliente mantendrá indemne al Proveedor frente a reclamos de terceros, incluidos sus Clientes Finales, que se deriven de un uso ilícito de la Aplicación, del incumplimiento de estos Términos o del tratamiento de datos personales sin la base legal exigible. Esta obligación no aplica cuando el reclamo se origine en una falta del propio Proveedor.

## 20. Vigencia, terminación y devolución de datos

20.1. Estos Términos rigen mientras el Cliente mantenga una Cuenta activa o utilice el Servicio.

20.2. **Terminación por el Cliente.** El Cliente puede dar por terminado el Servicio en cualquier momento, con un aviso escrito de al menos quince (15) días calendario antes del siguiente ciclo de pago, sin penalidad alguna. Podrá también solicitar la eliminación de su Cuenta mediante la función disponible en la Aplicación o por correo electrónico.

20.3. **Terminación por el Proveedor.** El Proveedor podrá terminar el Servicio por incumplimiento grave de estos Términos, previo aviso escrito y un plazo razonable para subsanar el incumplimiento, salvo que este ponga en riesgo la seguridad del Servicio o de otros usuarios, en cuyo caso podrá actuar de inmediato. También podrá descontinuar el Servicio con un aviso mínimo de sesenta (60) días, reembolsando la parte proporcional de lo pagado por períodos no prestados.

20.4. **Devolución y eliminación de datos.** Terminado el Servicio, el Cliente dispondrá de treinta (30) días calendario para solicitar y exportar su información en un formato de uso común. Vencido ese plazo, el Proveedor eliminará o anonimizará el Contenido del Cliente, salvo que una norma legal exija conservar determinada información. Los registros contables y fiscales del Cliente son de su responsabilidad.

20.5. Las cláusulas que por su naturaleza deban subsistir (propiedad intelectual, confidencialidad, limitación de responsabilidad y ley aplicable, entre otras) seguirán vigentes tras la terminación.

## 21. Modificaciones a los Términos

El Proveedor podrá actualizar estos Términos para reflejar cambios legales, técnicos o del Servicio. Los cambios sustanciales se comunicarán dentro de la Aplicación o por correo electrónico con al menos quince (15) días de anticipación a su entrada en vigencia, indicando la nueva versión. El uso del Servicio después de esa fecha, o la aceptación expresa cuando se solicite, implicará conformidad con los nuevos Términos. Si el Cliente no está de acuerdo, podrá terminar el Servicio conforme a la cláusula 20.2 sin penalidad.

## 22. Comunicaciones

Las comunicaciones del Proveedor se realizarán al correo electrónico registrado en la Cuenta o dentro de la Aplicación. El Usuario es responsable de mantener actualizado su correo. Las comunicaciones del Usuario al Proveedor se dirigirán al correo de contacto indicado en la cláusula 27.

## 23. Fuerza mayor

Ninguna de las partes será responsable por el incumplimiento o retraso en sus obligaciones, salvo las de pago, cuando se deba a hechos de fuerza mayor o caso fortuito, tales como desastres naturales, cortes generalizados de energía o de internet, fallas de proveedores de infraestructura, actos de autoridad o conflictos que escapen a su control razonable.

## 24. Disposiciones generales

- **Divisibilidad:** si alguna disposición de estos Términos se declara nula o inaplicable, las demás continuarán vigentes.
- **No renuncia:** la falta de ejercicio de un derecho no implica renuncia a él.
- **Cesión:** el Cliente no podrá ceder estos Términos sin autorización escrita del Proveedor. El Proveedor podrá cederlos a quien le suceda en la titularidad de la Aplicación, previa comunicación al Cliente.
- **Idioma:** estos Términos se redactan en español, que prevalecerá sobre cualquier traducción.

## 25. Ley aplicable y solución de controversias

25.1. Estos Términos se rigen por las leyes de la República de Panamá.

25.2. Las partes procurarán resolver cualquier diferencia de manera directa y amistosa, comunicándose por escrito, durante un plazo de treinta (30) días calendario.

25.3. Si no se alcanza una solución, la controversia se someterá a las autoridades y tribunales competentes de la República de Panamá, conforme a la ley. Cuando el Cliente tenga la condición de consumidor, podrá acudir también a la Autoridad de Protección al Consumidor y Defensa de la Competencia (ACODECO). Nada de lo dispuesto en este documento limita los derechos que la ley reconozca al consumidor.

## 26. Marco normativo de referencia

Estos Términos se redactan atendiendo, entre otras, a las siguientes normas de la República de Panamá, vigentes a la fecha de su elaboración:

- Ley 81 de 26 de marzo de 2019, sobre Protección de Datos Personales, y su reglamento, el Decreto Ejecutivo 285 de 28 de mayo de 2021.
- Ley 45 de 31 de octubre de 2007, sobre Protección al Consumidor y Defensa de la Competencia, y sus modificaciones.
- Ley 51 de 22 de julio de 2008, sobre documentos electrónicos, firmas electrónicas y comercio electrónico, modificada por la Ley 82 de 2012.
- Ley 256 de 26 de noviembre de 2021, sobre la obligación de expedir factura o documento equivalente, y demás normas de facturación de la Dirección General de Ingresos.
- Código de Comercio de la República de Panamá.

## 27. Contacto

Para consultas sobre estos Términos, soporte técnico, solicitudes relacionadas con datos personales o la eliminación de la Cuenta:

- **Proveedor:** Quevin Batista, operando como Green Garden Solutions
- **Correo electrónico:** quevinyahir28@gmail.com
- **Teléfono:** 6362-1418
''';

const String _kPrivacidadMarkdown = r'''
Esta Política de Privacidad explica, en lenguaje claro, qué datos personales trata la aplicación móvil Green Garden (la “Aplicación”), para qué los usa, con quién los comparte, cuánto tiempo los conserva y cómo puede usted ejercer sus derechos. Forma parte de los Términos y Condiciones de Uso y Servicio (los “Términos”), cuyas definiciones se aplican también aquí.

## 1. Quién es el responsable y cómo contactarlo

- **Proveedor:** Quevin Batista, persona natural, quien opera bajo el nombre comercial **Green Garden Solutions** (el “Proveedor”).
- **Correo electrónico:** quevinyahir28@gmail.com
- **Teléfono:** 6362-1418

Este es también el canal para consultas, reclamos y solicitudes sobre sus datos personales.

## 2. A quién se aplica y qué papel tiene cada parte

En la Aplicación hay dos grupos de datos, y el papel del Proveedor es distinto en cada uno:

- **Datos de su cuenta y de su negocio** (correo, contraseña, datos del negocio, logotipo, aceptación de los Términos). Para estos datos, el Proveedor es el **responsable del tratamiento**.
- **Datos de los Clientes Finales** que cada negocio registra en la Aplicación para llevar su agenda, cobros y facturas. Para estos datos, el **negocio que usa la Aplicación es el responsable** y el Proveedor actúa como **custodio de la base de datos**, es decir, los conserva y protege por cuenta del negocio y siguiendo sus instrucciones.

Si usted es Cliente Final de un negocio que utiliza Green Garden y desea ejercer sus derechos, debe dirigirse primero a ese negocio. El Proveedor le prestará la colaboración que corresponda para atender su solicitud.

## 3. Qué datos tratamos

3.1. **Datos de la cuenta y del negocio:**

- Correo electrónico y contraseña. La contraseña no se guarda en texto claro: el servicio de autenticación la protege con mecanismos criptográficos y el Proveedor no puede verla.
- Nombre comercial, operador responsable, teléfono y correo del negocio.
- Logotipo y color de marca que el usuario elige.
- Versión y fecha en que se aceptaron los Términos y esta Política.

3.2. **Datos de los Clientes Finales que registra el negocio:**

- Nombre, dirección o lugar del servicio y fecha del trabajo.
- Servicios contratados, precios, estado del trabajo y del cobro, y forma de pago (por ejemplo, Yappy o efectivo).
- Recurrencia del servicio y registro de las facturas y cotizaciones generadas.

La Aplicación no solicita el teléfono ni el correo de los Clientes Finales, ni datos de tarjetas, ni documentos de identidad. Si el negocio escribe otros datos personales en campos de texto libre, es su responsabilidad contar con la base legal para hacerlo.

3.3. **Datos de gestión del negocio:** inventario de herramientas e insumos, servicios y tarifas, e ingresos y gastos. Normalmente no contienen datos personales de terceros.

3.4. **Datos técnicos mínimos:** identificador de la cuenta, información de la sesión de acceso y registros técnicos que generan los proveedores de infraestructura para operar y proteger el servicio, que pueden incluir la dirección IP y el tipo de dispositivo.

3.5. **Lo que la Aplicación no recopila:**

- **Datos biométricos.** La huella o el rostro los verifica el sistema operativo del teléfono; la Aplicación solo recibe un resultado de “aprobado” o “no aprobado” y nunca accede a la huella ni a la imagen del rostro.
- Ubicación por GPS ni la lista de contactos del teléfono.
- Publicidad, ni seguimiento con fines publicitarios, ni herramientas de análisis de comportamiento de uso.
- Datos de tarjetas bancarias ni pagos. La Aplicación solo registra cómo pagó un cliente.
- Acceso a la galería de fotos del teléfono, salvo la imagen que usted elige como logotipo.

## 4. Para qué usamos los datos

Los datos se tratan únicamente para fines determinados y compatibles entre sí:

- Prestar el Servicio: agenda, clientes, inventario, finanzas, cotizaciones, facturas en PDF, recordatorios y sincronización.
- Crear y proteger su cuenta, incluido el envío de códigos de verificación por correo electrónico.
- Brindar soporte técnico y corregir fallas.
- Enviar avisos relacionados con el Servicio, como cambios en los Términos, incidentes de seguridad o interrupciones.
- Cumplir obligaciones legales y atender requerimientos de autoridades competentes.

El Proveedor no vende los datos, no los cede a terceros con fines propios y no los utiliza para publicidad ni para perfilar personas.

## 5. Base del tratamiento y consentimiento

Cada tratamiento se apoya en la condición que le corresponde, y aceptar estos documentos no convierte todos los tratamientos en dependientes del consentimiento. En concreto: los datos de la cuenta y del negocio se tratan porque son necesarios para crear su cuenta y prestar el Servicio que usted contrató; la autorización de la transferencia internacional y el registro de la aceptación de estos documentos se basan en su consentimiento; y los datos que deban conservarse o entregarse por mandato de una norma o autoridad se tratan por obligación legal. El Proveedor registra la fecha y la versión de cada aceptación como constancia. Cuando el negocio registre datos de sus Clientes Finales, es el negocio quien debe contar con la base legal o el consentimiento de ellos.

## 6. Con quién compartimos los datos

Para que la Aplicación funcione, el Proveedor se apoya en terceros que tratan datos únicamente para prestar su servicio:

- **Supabase:** alojamiento de la base de datos, autenticación de usuarios y almacenamiento de archivos como el logotipo. Recibe los datos descritos en la sección 3.
- **Servicio de correo electrónico:** envío de los códigos de verificación y recuperación de contraseña. Recibe únicamente su correo electrónico y el contenido del mensaje. Actualmente se utiliza el servicio de correo de Google (Gmail), y el Proveedor podrá cambiar de proveedor. Si el cambio afecta de forma material el tratamiento o las transferencias de datos, lo informará antes de aplicarlo y pedirá una nueva aceptación cuando corresponda.
- **Autoridades:** cuando una ley, una orden judicial o un requerimiento de autoridad competente lo exija.

Si usted descarga la Aplicación desde una tienda de aplicaciones, la tienda trata los datos de la descarga según su propia política de privacidad.

El Proveedor no vende ni cede datos a otras personas o empresas.

## 7. Transferencia internacional de datos

El proyecto del Proveedor en Supabase está alojado en la región **East US (North Virginia), Estados Unidos**. Por lo tanto, los datos que usted ingrese en la Aplicación se almacenan y procesan fuera de la República de Panamá. Lo mismo puede ocurrir con el servicio de correo electrónico.

Esta transferencia es necesaria para prestar el Servicio. Respecto de los datos de su cuenta, usted la autoriza expresamente en un paso separado de la aceptación general, y esa autorización se registra aparte. Respecto de los datos de los Clientes Finales, el negocio responsable debe contar con la base legal que corresponda; el Proveedor le informa la ubicación de los servidores para que pueda cumplir sus propios deberes de información. El Proveedor procura que sus proveedores ofrezcan medidas de protección adecuadas, y aplica cifrado en la comunicación y acceso restringido a la información.

## 8. Qué se guarda solo en su teléfono

Algunos datos permanecen únicamente en el dispositivo:

- El logotipo y el color de marca guardados temporalmente para mostrarlos antes de iniciar sesión.
- Su preferencia de acceso con huella o rostro.
- Las operaciones hechas sin conexión que aún esperan sincronizarse.
- Los recordatorios locales programados.

Al cerrar sesión se eliminan del teléfono los datos cargados en la Aplicación, los recordatorios programados y las operaciones pendientes de sincronizar (por eso conviene sincronizar antes de cerrar sesión), y se borra su preferencia de acceso con huella o rostro. El logotipo y el color de marca guardados permanecen en el teléfono para mostrarlos en la pantalla de acceso. Al desinstalar la Aplicación, los datos guardados en el teléfono normalmente se eliminan, y los que aún no se hubieran sincronizado se pierden. El comportamiento de los datos locales puede variar según el sistema operativo.

## 9. Cuánto tiempo conservamos los datos

- Datos de la cuenta, de los Clientes Finales y de gestión del negocio: mientras la cuenta esté activa, para poder prestar el Servicio.
- Al terminar el Servicio, el Cliente dispone de treinta (30) días calendario para solicitar y exportar su información. Vencido ese plazo, los datos se eliminan o se anonimizan, salvo que una norma legal exija conservar determinada información. Ese plazo existe para facilitar la exportación y no limita sus derechos legales de cancelación.
- Las copias de seguridad del proveedor de infraestructura pueden conservar los datos durante un período limitado, hasta que se eliminen según el ciclo de respaldos del proveedor de infraestructura. Durante ese tiempo permanecen protegidas y no se utilizan para prestar el Servicio. Los registros técnicos que generan esos proveedores se conservan según su propio ciclo.
- Los registros contables y fiscales del negocio son responsabilidad de cada negocio.

## 10. Cómo protegemos los datos

El Proveedor aplica medidas técnicas y organizativas razonables, entre ellas:

- Aislamiento de los datos por cuenta mediante políticas de seguridad a nivel de base de datos, de modo que cada cuenta accede únicamente a su información.
- Comunicación cifrada entre la Aplicación y el servidor.
- Protección criptográfica de las contraseñas (no se guardan en texto claro) y verificación del correo mediante códigos.
- Acceso restringido a la información y deber de confidencialidad.
- Bloqueo opcional de la Aplicación con huella o rostro.

Ningún sistema es absolutamente invulnerable. Si el Proveedor detecta una violación de seguridad que afecte sus datos, lo informará de inmediato al negocio responsable, con la información disponible, los datos afectados y las medidas de contención adoptadas. Conservará un registro del incidente y colaborará para que el negocio pueda cumplir las notificaciones que la ley le exija frente a las autoridades y a los titulares. Ese aviso no sustituye las obligaciones legales del responsable.

## 11. Sus derechos

La ley le reconoce los siguientes derechos sobre sus datos personales:

- **Acceso:** saber qué datos suyos se tratan y para qué.
- **Rectificación:** pedir que se corrijan datos inexactos o incompletos.
- **Cancelación:** pedir que se eliminen sus datos cuando proceda.
- **Oposición:** oponerse a un tratamiento en los casos que la ley permite.
- **Portabilidad:** recibir sus datos en un formato de uso común.

Puede retirar su consentimiento cuando la ley lo permita. Retirarlo detiene los tratamientos que dependan de él, sin afectar los que tengan otra base legal válida, como los necesarios para prestarle el Servicio. Si un dato es imprescindible para una función de la Aplicación, esa función dejaría de estar disponible para usted y se lo indicaremos.

**Cómo ejercerlos:** escriba a quevinyahir28@gmail.com indicando su nombre, el correo de su cuenta, el derecho que desea ejercer y una descripción de su solicitud. El Proveedor podrá pedirle información para verificar su identidad. Su solicitud se atenderá dentro de los plazos que establece la ley.

**Si usted es Cliente Final de un negocio:** dirija su solicitud al negocio que registró sus datos, que es su responsable. Si usted contacta directamente al Proveedor, este remitirá su solicitud al negocio responsable de inmediato y colaborará con él para que pueda responder dentro de los plazos legales. El plazo de primera respuesta del soporte técnico no es el plazo para gestionar solicitudes de derechos personales.

Si considera que sus derechos no han sido atendidos, puede presentar un reclamo ante la Autoridad Nacional de Transparencia y Acceso a la Información (ANTAI), que es la autoridad de control en materia de protección de datos personales.

## 12. Menores de edad

La Aplicación está dirigida a personas mayores de edad y a negocios, no a menores de edad. Cada negocio debe asegurarse de contar con la base legal y las autorizaciones que correspondan para los datos que registre, incluidos los de menores. Si usted cree que se registraron datos de un menor sin la autorización debida, escríbanos para que se atienda su solicitud.

## 13. Decisiones automatizadas

La Aplicación no toma decisiones automatizadas que produzcan efectos jurídicos sobre las personas ni elabora perfiles de ellas.

## 14. Cambios en esta Política

El Proveedor podrá actualizar esta Política para reflejar cambios legales, técnicos o del Servicio, por ejemplo, si cambia de proveedor de infraestructura o de correo. Los cambios importantes se comunicarán dentro de la Aplicación o por correo electrónico con al menos quince (15) días de anticipación e indicarán la nueva versión. Se le pedirá aceptar la nueva versión cuando el cambio modifique las finalidades del tratamiento, incorpore nuevos proveedores o transferencias, o cuando la ley exija un nuevo consentimiento. El aviso previo no sustituye las obligaciones de información ni el consentimiento que pudieran ser necesarios para nuevos tratamientos. El Proveedor conserva un registro de la versión y la fecha de cada aceptación.

## 15. Marco normativo de referencia

Esta Política se elabora atendiendo, entre otras, a las siguientes normas de la República de Panamá, vigentes a la fecha de su elaboración:

- Ley 81 de 26 de marzo de 2019, sobre Protección de Datos Personales, y su reglamento, el Decreto Ejecutivo 285 de 28 de mayo de 2021.
- Ley 51 de 22 de julio de 2008, sobre documentos electrónicos, firmas electrónicas y comercio electrónico, modificada por la Ley 82 de 2012.
- Ley 45 de 31 de octubre de 2007, sobre Protección al Consumidor y Defensa de la Competencia, y sus modificaciones.

## 16. Contacto

Para consultas sobre esta Política, ejercicio de derechos o reclamos:

- **Proveedor:** Quevin Batista, operando como Green Garden Solutions
- **Correo electrónico:** quevinyahir28@gmail.com
- **Teléfono:** 6362-1418
''';