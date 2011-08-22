/*
 * Copyright (C) 2003 cajus <cajus@debian.org>
 */

#include "kprogress.h"

#include <qstringlist.h>
#include <qwidget.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>


kprogress::kprogress()
    : QWidget( 0, "kprogress")
{
  resize (500,70);

  QFrame *f= new QFrame(this);
  f->resize (500,70);
  f->setFrameStyle(QFrame::Panel | QFrame::Raised );
  f->setLineWidth( 2 );

  status= new QLabel(f, "status label" );
  status->setGeometry (53, 8, 438,30);
  progress= new QProgressBar(f, "progress bar");
  progress->setGeometry (53, 36, 438,20);
  progress->setTotalSteps (100);

  QLabel *ic= new QLabel(f, "icon label");
  ic->setGeometry (2,8, 48, 48);
  ic->setPixmap (QPixmap("/usr/share/apps/kprogress/install.png"));

  // Open stdin non blocking
  fcntl (0, F_SETFL, O_NONBLOCK);

  // Initialize timer for tail on stdin
  tail= new QTimer(f);
  connect (tail, SIGNAL(timeout()), this, SLOT(readinput()));
  tail->start(500);
}

kprogress::~kprogress()
{
  tail->stop();
}

void kprogress::readinput()
{
  char buffer[1024];
  int size;
  int step;
  int pos;

  /* format is "int string" */
  size= read (0, buffer, 1023 );
  if (size > 0)
  {

    /* Line end */
    buffer[size]= 0;

    /* Walk through the buffer, line by line */
    QString newstatus;
    newstatus.sprintf("%s", buffer);
    QStringList lines= QStringList::split('\n', newstatus);

    for ( QStringList::Iterator it = lines.begin(); it != lines.end(); ++it ) {
      (*it).replace( '\n', "" );
      pos= (*it).find(' ');
      status->setText ((*it).mid(pos));
      step= atoi((*it).ascii());
      if (step > 100)
      {
        step= 100;
      }
      if (step < 0)
      {
        exit(0);
      }
      progress->setProgress (step);
    }
  }
}

#include "kprogress.moc"
