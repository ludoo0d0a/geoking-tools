source .env
# Per-target DeepL context is auto-built from doc/tennis-glossary.md
# (compact per-language sections), so canonical tennis terms — like
# game=jeu (not "partie") or break=break (not "pause") — bias DeepL.
python3 translate.py --mode forward --modules app shared wear --batch-size 25

# all modules, 1 language
#python3 translate.py --mode forward --modules app shared wear --batch-size 25 --languages tr

# 1 module, 3 languages
#python3 translate.py --mode forward --modules wear --batch-size 25 --languages sv tr zh