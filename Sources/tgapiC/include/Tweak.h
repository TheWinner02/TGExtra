#ifdef __cplusplus
extern "C" {
#endif

int TGExtraRebindSymbol(const char *symbolName, void *replacement, void **original);
int TGExtraDynamicInterpose(void *replacee, void *replacement);

#ifdef __cplusplus
}
#endif
