# TaskFlow

Aplicación web de gestión de tareas en español, desarrollada con React, TypeScript, Vite y Tailwind CSS. Puedes agregar tareas, marcar o desmarcar su estado y eliminarlas. Las tareas se conservan al recargar gracias a LocalStorage.

## Desarrollo local

Requiere Node.js 20.19 o superior en la rama 20, o Node.js 22.12 o posterior, y npm.

```bash
npm ci
npm run dev
```

Abre la dirección que muestra Vite en la terminal.

## Comandos

| Comando | Resultado |
| --- | --- |
| `npm test` | Ejecuta las pruebas unitarias con Vitest. |
| `npm run test:watch` | Vuelve a ejecutar las pruebas al cambiar los archivos. |
| `npm run lint` | Analiza el código con ESLint. |
| `npm run build` | Comprueba los tipos y genera la compilación en `dist/`. |
| `npm run preview` | Sirve localmente la compilación generada. |

## Estructura

- `src/components/` contiene el formulario y la lista de tareas.
- `src/services/` valida, lee y guarda los datos en LocalStorage.
- `src/types/` define el modelo de las tareas.
- `src/utils/` contiene la validación de títulos y las operaciones sobre la lista.

Las tareas se guardan en el perfil y origen actuales del navegador. Si el almacenamiento falla, la aplicación muestra un aviso y permite seguir trabajando en la sesión actual.

## CI/CD con GitHub Actions y AWS Amplify Hosting

El workflow [TaskFlow CI/CD](.github/workflows/ci-cd.yml) ejecuta CI con Node.js 22 en pushes a `main`, pull requests con destino a `main` y ejecuciones manuales. CI instala con `npm ci`, ejecuta ESLint, comprueba TypeScript, corre Vitest y bloquea vulnerabilidades altas y críticas con `npm audit --audit-level=high`. Si todas las comprobaciones pasan, compila y publica un artefacto con `taskflow-<SHA>.zip` y su checksum SHA-256. El ZIP contiene `index.html` en la raíz.

CD requiere un push a `main`, CI exitoso y `ENABLE_DEPLOYMENT=true`. Descarga el artefacto de esa ejecución, verifica el checksum y usa credenciales temporales de AWS mediante OIDC. El [script de despliegue](scripts/deploy-amplify.sh) carga el ZIP por HTTPS, espera el estado `SUCCEED` de Amplify y comprueba que el sitio responda con HTTP 2xx. El job promociona el ZIP de CI directamente y serializa los despliegues sin cancelar el que está en curso. Antes de solicitar credenciales, comprueba que el commit siga en la punta de `main` para omitir ejecuciones atrasadas.

### Configuración manual en AWS

1. Prepara una aplicación estática y una rama de destino en Amplify Hosting con **Deploy without Git**. Puedes reutilizar una aplicación configurada para despliegues manuales. Anota su ID, región, rama y URL HTTPS pública. [Guía de despliegue manual de AWS Amplify](https://docs.aws.amazon.com/amplify/latest/userguide/manual-deploys.html)
2. En IAM, configura el proveedor de identidad OpenID Connect con URL `https://token.actions.githubusercontent.com` y audiencia `sts.amazonaws.com`. Si ya existe, reutilízalo. [Configuración de OIDC para AWS en GitHub Actions](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws)
3. Crea un rol con el ejemplo de [política de confianza OIDC](docs/iam/github-oidc-trust.json). Sustituye `<ACCOUNT_ID>`, `<OWNER>` y `<REPOSITORY>` por los valores de tu cuenta y repositorio. La política usa el sujeto OIDC de la rama `main`. Si el repositorio usa sujetos OIDC inmutables, incluidos los repositorios creados después del 15 de julio de 2026, usa el valor exacto `repo:<OWNER>@<OWNER_ID>/<REPOSITORY>@<REPOSITORY_ID>:ref:refs/heads/main` en la condición `sub`. [Formatos del sujeto OIDC en GitHub](https://docs.github.com/en/actions/how-tos/secure-your-work/security-harden-deployments/oidc-in-aws#configuring-the-role-and-trust-policy)
4. Adjunta al rol la [política de despliegue de Amplify](docs/iam/amplify-deploy-permissions.json) tras reemplazar `<REGION>`, `<ACCOUNT_ID>`, `<APP_ID>` y `<BRANCH_NAME>`. Los permisos se limitan a iniciar despliegues en la rama indicada y consultar sus jobs. Copia el ARN del rol. [Referencia de permisos de AWS Amplify](https://docs.aws.amazon.com/service-authorization/latest/reference/list_amplify.html)

### Configuración manual en GitHub

En **Settings → Secrets and variables → Actions → Variables**, crea las siguientes variables del repositorio.

| Variable | Valor |
| --- | --- |
| `AWS_REGION` | Región de la aplicación de Amplify, por ejemplo `us-east-1`. |
| `AWS_ROLE_ARN` | ARN del rol IAM que confía en GitHub mediante OIDC. |
| `AMPLIFY_APP_ID` | ID de la aplicación de Amplify Hosting. |
| `AMPLIFY_BRANCH_NAME` | Rama de Amplify cubierta por la política del rol, por ejemplo `production`. |
| `AMPLIFY_SITE_URL` | URL pública HTTPS del sitio, sin credenciales ni parámetros. |
| `ENABLE_DEPLOYMENT` | Usa `false` mientras verificas CI. Cámbiala a `true` cuando autorices los despliegues. |

Protege `main` con revisiones obligatorias y el check **Continuous Integration**. Verifica CI desde **Actions → TaskFlow CI/CD → Run workflow** y comprueba que el artefacto incluya el ZIP y el checksum. El primer push autorizado a `main` con CD habilitado inicia el despliegue.
