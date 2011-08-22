/*
 * Copyright (C) 2003 cajus <cajus@debian.org>
 */

#ifndef _KPROGRESS_H_
#define _KPROGRESS_H_

#ifdef HAVE_CONFIG_H
#include <config.h>
#endif

#include <qwidget.h>
#include <qprogressbar.h>
#include <qlabel.h>
#include <qpixmap.h>
#include <qtimer.h>

/**
 * @short Application Main Window
 * @author cajus <cajus@debian.org>
 * @version 0.1
 */
class kprogress : public QWidget
{
    Q_OBJECT
public:
    /**
     * Default Constructor
     */
    kprogress();

    /**
     * Default Destructor
     */
    virtual ~kprogress();

private:
    /**
     * Status label
     */
     QLabel *status;

     /**
      * Read timer
      */
      QTimer *tail;
      int input;

      QProgressBar *progress;

private slots:
      void readinput();
};

#endif // _KPROGRESS_H_
