/*

Copyright (C) 2013-2019 John W. Eaton
Copyright (C) 2011-2019 Jacob Dawid

This file is part of Octave.

Octave is free software: you can redistribute it and/or modify it
under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Octave is distributed in the hope that it will be useful, but
WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Octave; see the file COPYING.  If not, see
<https://www.gnu.org/licenses/>.

*/

#if defined (HAVE_CONFIG_H)
#  include "config.h"
#endif

#include <utility>

#include <QApplication>
#include <QFile>
#include <QTextCodec>
#include <QThread>
#include <QTimer>
#include <QTranslator>

#include "interpreter-qobject.h"
#include "main-window.h"
#include "octave-qobject.h"
#include "qt-application.h"
#include "qt-interpreter-events.h"
#include "resource-manager.h"

#if defined (Q_OS_MAC)
   // ObjC interface is needed for App Nap control
#  include <objc/runtime.h>
#  include <objc/message.h>
#endif

#include "oct-env.h"
#include "version.h"

#include "ovl.h"

namespace octave
{
  // Disable all Qt messages by default.

  static void
#if defined (QTMESSAGEHANDLER_ACCEPTS_QMESSAGELOGCONTEXT)
  message_handler (QtMsgType, const QMessageLogContext &, const QString &)
#else
  message_handler (QtMsgType, const char *)
#endif
  { }

  //! Reimplement QApplication::notify.  Octave's own exceptions are
  //! caught and rethrown in the interpreter thread.

  bool octave_qapplication::notify (QObject *receiver, QEvent *ev)
  {
    try
      {
        return QApplication::notify (receiver, ev);
      }
    catch (execution_exception& ee)
      {
        emit interpreter_event
          ([ee] (void)
           {
             // INTERPRETER THREAD

             throw ee;
           });
      }

   return false;
  }

  // We will create a QApplication object, even if START_GUI is false,
  // so that we can use Qt widgets for plot windows when running in
  // command-line mode.  Note that we are creating an
  // octave_qapplication object but handling it as a QApplication object
  // because the octave_qapplication should behave identically to a
  // QApplication object except that it overrides the notify method so
  // we can handle forward Octave interpreter exceptions from the GUI
  // thread to the interpreter thread.

  base_qobject::base_qobject (qt_application& app_context)
    : QObject (), m_app_context (app_context),
      m_argc (m_app_context.sys_argc ()),
      m_argv (m_app_context.sys_argv ()),
      m_qapplication (new octave_qapplication (m_argc, m_argv)),
      m_qt_tr (new QTranslator ()), m_gui_tr (new QTranslator ()),
      m_qsci_tr (new QTranslator ()), m_translators_installed (false),
      m_interpreter_qobj (new interpreter_qobject (this)),
      m_main_thread (new QThread ())
  {
    std::string show_gui_msgs =
      sys::env::getenv ("OCTAVE_SHOW_GUI_MESSAGES");

    // Installing our handler suppresses the messages.

    if (show_gui_msgs.empty ())
      {
#if defined (HAVE_QINSTALLMESSAGEHANDLER)
        qInstallMessageHandler (message_handler);
#else
        qInstallMsgHandler (message_handler);
#endif
      }

    // Set the codec for all strings (before wizard or any GUI object)
#if ! defined (Q_OS_WIN32)
    QTextCodec::setCodecForLocale (QTextCodec::codecForName ("UTF-8"));
#endif

#if defined (HAVE_QT4)
    QTextCodec::setCodecForCStrings (QTextCodec::codecForName ("UTF-8"));
#endif

    // Initialize global Qt application metadata.

    QCoreApplication::setApplicationName ("GNU Octave");
    QCoreApplication::setApplicationVersion (OCTAVE_VERSION);

    // Register octave_value_list for connecting thread crossing signals.

    qRegisterMetaType<octave_value_list> ("octave_value_list");

#if defined (Q_OS_MAC)
    // Mac App Nap feature causes pause() and sleep() to misbehave.
    // Disable it for the entire program run.
    disable_app_nap ();
#endif

    // Force left-to-right alignment (see bug #46204)
    m_qapplication->setLayoutDirection (Qt::LeftToRight);

    connect (m_interpreter_qobj, SIGNAL (octave_finished_signal (int)),
             this, SLOT (handle_octave_finished (int)));

    connect (m_main_thread, SIGNAL (finished (void)),
             m_main_thread, SLOT (deleteLater (void)));

    // Handle any interpreter_event signal from the octave_qapplication
    // object here.

    connect (m_qapplication, SIGNAL (interpreter_event (const fcn_callback&)),
             this, SLOT (interpreter_event (const fcn_callback&)));

    connect (m_qapplication, SIGNAL (interpreter_event (const meth_callback&)),
             this, SLOT (interpreter_event (const meth_callback&)));
  }

  base_qobject::~base_qobject (void)
  {
    // Note that we don't delete m_main_thread here.  That is handled by
    // deleteLater slot that is called when the m_main_thread issues a
    // finished signal.

    delete m_interpreter_qobj;
    delete m_qsci_tr;
    delete m_gui_tr;
    delete m_qt_tr;
    delete m_qapplication;

    string_vector::delete_c_str_vec (m_argv);
  }

#if defined (Q_OS_MAC)
  // FIXME: Does this need to be a private member function of base_qobject?
  //        Or should it be a file local static function?
  void disable_app_nap (void)
  {
    Class process_info_class;
    SEL process_info_selector;
    SEL begin_activity_with_options_selector;
    id process_info;
    id reason_string;

    // Option codes found at https://stackoverflow.com/questions/22784886/what-can-make-nanosleep-drift-with-exactly-10-sec-on-mac-os-x-10-9/32729281#32729281
    unsigned long long NSActivityUserInitiatedAllowingIdleSystemSleep = 0x00FFFFFFULL;
    unsigned long long NSActivityLatencyCritical = 0xFF00000000ULL;

    // Avoid errors on older versions of OS X
    process_info_class = static_cast<Class> (objc_getClass ("NSProcessInfo"));
    if (process_info_class == nil)
      return;

    process_info_selector = sel_getUid ("processInfo");
    if (class_getClassMethod (process_info_class, process_info_selector) == NULL)
      return;

    begin_activity_with_options_selector = sel_getUid ("beginActivityWithOptions:reason:");
    if (class_getInstanceMethod (process_info_class,
                                 begin_activity_with_options_selector) == NULL)
      return;

    if ((process_info = objc_msgSend (static_cast<id> (process_info_class), process_info_selector)) == nil)
      return;

    reason_string = objc_msgSend (objc_getClass ("NSString"),
                                  sel_getUid ("alloc"));
    reason_string = objc_msgSend (reason_string,
                                  sel_getUid ("initWithUTF8String:"),
                                  "App Nap causes pause() malfunction");

    // Start an Activity that suppresses App Nap.  This Activity will run for
    // the entire duration of the Octave process.  This is intentional,
    // not a leak.
    osx_latencycritical_activity = objc_msgSend (process_info,
        begin_activity_with_options_selector,
        NSActivityUserInitiatedAllowingIdleSystemSleep | NSActivityLatencyCritical,
        reason_string);
  }
#endif

  void base_qobject::config_translators (void)
  {
    if (m_translators_installed)
      return;

    resource_manager::config_translators (m_qt_tr, m_qsci_tr, m_gui_tr);

    m_qapplication->installTranslator (m_qt_tr);
    m_qapplication->installTranslator (m_gui_tr);
    m_qapplication->installTranslator (m_qsci_tr);

    m_translators_installed = true;
  }

  void base_qobject::start_main_thread (void)
  {
    // Defer initializing and executing the interpreter until after the main
    // window and QApplication are running to prevent race conditions
    QTimer::singleShot (0, m_interpreter_qobj, SLOT (execute (void)));

    m_interpreter_qobj->moveToThread (m_main_thread);

    m_main_thread->start ();
  }

  int base_qobject::exec (void)
  {
    return m_qapplication->exec ();
  }

  void base_qobject::handle_octave_finished (int exit_status)
  {
#if defined (Q_OS_MAC)
    // fprintf to stderr is needed by macOS, for poorly-understood reasons.
    fprintf (stderr, "\n");
#endif

    m_main_thread->quit ();

    qApp->exit (exit_status);
  }

  void base_qobject::interpreter_event (const fcn_callback& fcn)
  {
    // The following is a direct function call across threads.  It works
    // because the it is accessing a thread-safe queue of events that
    // are later executed by the Octave interpreter in the other thread.

    // See also the comments in interpreter-qobject.h about
    // interpreter_qobject slots.

    m_interpreter_qobj->interpreter_event (fcn);
  }

  void base_qobject::interpreter_event (const meth_callback& meth)
  {
    // The following is a direct function call across threads.  It works
    // because the it is accessing a thread-safe queue of events that
    // are later executed by the Octave interpreter in the other thread.

    // See also the comments in interpreter-qobject.h about
    // interpreter_qobject slots.

    m_interpreter_qobj->interpreter_event (meth);
  }

  void base_qobject::confirm_shutdown_octave (void)
  {
    m_interpreter_qobj->confirm_shutdown (true);
  }

  void base_qobject::copy_image_to_clipboard (const QString& file,
                                              bool remove_file)
  {
    QClipboard *clipboard = QApplication::clipboard ();

    QImage img (file);

    if (img.isNull ())
      {
        // Report error?
        return;
      }

    clipboard->setImage (img);

    if (remove_file)
      QFile::remove (file);
  }

  cli_qobject::cli_qobject (qt_application& app_context)
    : base_qobject (app_context)
  {
    // Get settings file.
    resource_manager::reload_settings ();

    // After settings.
    config_translators ();

    m_qapplication->setQuitOnLastWindowClosed (false);

    start_main_thread ();
  }

  gui_qobject::gui_qobject (qt_application& app_context)
    : base_qobject (app_context), m_main_window (new main_window (*this))
  {
    connect (m_interpreter_qobj, SIGNAL (octave_ready_signal (void)),
             m_main_window, SLOT (handle_octave_ready (void)));

    m_app_context.gui_running (true);

    start_main_thread ();
  }

  gui_qobject::~gui_qobject (void)
  {
    delete m_main_window;
  }

  void gui_qobject::confirm_shutdown_octave (void)
  {
    bool closenow = true;

    if (m_main_window)
      closenow = m_main_window->confirm_shutdown_octave ();

    m_interpreter_qobj->confirm_shutdown (closenow);
  }
}
