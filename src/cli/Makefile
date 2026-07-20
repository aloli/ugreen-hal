# Makefile FreeBSD pour ugreen-led-ctl.
#
# Style bsd.prog.mk volontairement : c'est ce qu'attend un relecteur venant
# de FreeBSD, zVault ou XigmaNAS, et cela évite de réinventer des règles de
# construction que le système fournit déjà.
#
#   make            construit ugreen-led-ctl
#   make clean      nettoie
#   make install    installe dans /usr/local/bin (DESTDIR honoré)
#
# Ne se construit que sous FreeBSD : le code dépend de dev/smbus/smb.h.

PROG=	ugreen-led-ctl
SRCS=	ugreen-led-ctl.c

# Pas encore de page de manuel — à écrire quand le pilote aura été validé
# sur matériel réel, documenter une commande non testée serait prématuré.
MAN=

BINDIR?=	/usr/local/bin

CFLAGS+=	-std=c99
CFLAGS+=	-Wall -Wextra

.include <bsd.prog.mk>
