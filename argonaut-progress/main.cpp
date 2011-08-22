/*
 * Copyright (C) 2003 cajus <cajus@debian.org>
 */

#include "kprogress.h"
#include <qapplication.h>
#include <qwidget.h>

static const char version[] = "0.1";

int main(int argc, char **argv)
{
    QApplication *app= new QApplication(argc, argv);
    kprogress *mainWin = 0;

    mainWin = new kprogress();
    app->setMainWidget( mainWin );
    mainWin->show();

    // mainWin has WDestructiveClose flag by default, so it will delete itself.
    return app->exec();
}

