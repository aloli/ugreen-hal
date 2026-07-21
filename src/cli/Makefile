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

# Édition de liens statique par défaut.
#
# Le binaire est construit sur une machine de développement et copié sur le
# NAS, où tourne une distribution dont la version de FreeBSD diffère —
# zVault est basé sur FreeBSD 13.3, XigmaNAS sur 14.x. FreeBSD garantit la
# compatibilité ascendante (un binaire ancien tourne sur un système plus
# récent) mais pas l'inverse : un exécutable lié dynamiquement contre la
# libc de FreeBSD 15 échouerait sur 13.3, faute des versions de symboles
# attendues.
#
# Le programme n'utilise que la libc : le coût du statique se limite à
# quelques centaines de kilo-octets, contre une classe entière de pannes
# évitées au moment précis où l'on cherche à savoir si une LED s'allume.
#
#   make                  binaire statique, portable
#   make NO_SHARED=no     binaire dynamique, plus léger, non portable
NO_SHARED?=	yes

.include <bsd.prog.mk>
