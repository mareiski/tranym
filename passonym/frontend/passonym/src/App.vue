```vue
<script setup lang="ts">
import { ref, onMounted, onBeforeUnmount } from 'vue'
import type { ProofResult, QueryResult } from '@zkpassport/sdk'
import { mountVerifyButton } from '@zkpassport/ui/button'

// Diese Funktion muss aus deiner bestehenden Implementierung kommen.
// Sie muss für denselben Nutzer einen stabilen Identifikator liefern.
import { getOrCreateSignature } from '@/services/identity'

type VerifyResponse = {
  verified: boolean
  token?: string
  error?: string
}

type RegisterResponse = {
  registered: boolean
  error?: string
}

type FlowStatus = 'initializing' | 'ready' | 'verifying' | 'registering' | 'success' | 'error'

const identityServerUrl = (
  import.meta.env.VITE_IDENTITY_SERVER_URL ?? 'http://localhost:3000'
).replace(/\/$/, '')

const platformServerUrl = (
  import.meta.env.VITE_PLATFORM_SERVER_URL ?? 'http://localhost:4000'
).replace(/\/$/, '')

const status = ref<FlowStatus>('initializing')
const statusMessage = ref('ZKPassport wird vorbereitet …')
const errorMessage = ref('')
const isBusy = ref(false)

let mounted = false

onMounted(async () => {
  mounted = true

  const container = document.getElementById('zkpassport')

  if (!container) {
    showError('Das Verifizierungselement wurde nicht gefunden.')
    return
  }

  try {
    // Die Identität wird einmal für diesen Ablauf ermittelt.
    const signature = await getOrCreateSignature()

    if (!mounted) return

    mountVerifyButton(container, {
      purpose: 'Prove your personhood',

      service: {
        scope: 'personhood',
        devMode: import.meta.env.DEV,
      },

      query: {
        nationality: {
          included: ['Zero Knowledge Republic'],
        },
      },

      onSuccess: async ({ proofs, result }: { proofs: ProofResult[]; result: QueryResult }) => {
        // Verhindert parallele Verifizierungs- und Registrierungsabläufe.
        if (isBusy.value) return false

        isBusy.value = true
        errorMessage.value = ''

        try {
          status.value = 'verifying'
          statusMessage.value = 'Deine Nachweise werden überprüft …'

          const verifyResult = await verifyProofs(proofs, result, signature)

          if (!verifyResult.verified || !verifyResult.token) {
            throw new Error(verifyResult.error ?? 'Die Identitätsprüfung war nicht erfolgreich.')
          }

          status.value = 'registering'
          statusMessage.value = 'Deine Identität wird registriert …'

          const registered = await registerWithToken(verifyResult.token)

          if (!registered) {
            throw new Error('Die Registrierung wurde abgelehnt.')
          }

          status.value = 'success'
          statusMessage.value = 'Verifizierung und Registrierung erfolgreich!'

          return true
        } catch (error: unknown) {
          showError(getErrorMessage(error))
          return false
        } finally {
          isBusy.value = false
        }
      },
    })

    status.value = 'ready'
    statusMessage.value = 'Du kannst jetzt die Identitätsprüfung starten.'
  } catch (error: unknown) {
    showError(getErrorMessage(error))
  }
})

onBeforeUnmount(() => {
  mounted = false
})

async function verifyProofs(
  proofs: ProofResult[],
  result: QueryResult,
  signature: string,
): Promise<VerifyResponse> {
  const response = await fetch(`${identityServerUrl}/api/verify`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      proofs,
      result,
      signature,
    }),
  })

  const data = await readJson<VerifyResponse>(response)

  if (!response.ok) {
    throw new Error(data.error ?? `Identity-Server antwortet mit HTTP ${response.status}.`)
  }

  return data
}

async function registerWithToken(token: string): Promise<boolean> {
  const response = await fetch(`${platformServerUrl}/api/register`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({
      // Nur senden, wenn dein Platform-Server dieses Feld benötigt.
      // Die Identität sollte ansonsten aus dem validierten Token kommen.
    }),
  })

  const data = await readJson<RegisterResponse>(response)

  if (!response.ok) {
    throw new Error(data.error ?? `Platform-Server antwortet mit HTTP ${response.status}.`)
  }

  return data.registered === true
}

async function readJson<T>(response: Response): Promise<T> {
  try {
    return (await response.json()) as T
  } catch {
    throw new Error('Der Server hat keine gültige JSON-Antwort geliefert.')
  }
}

function showError(message: string) {
  status.value = 'error'
  statusMessage.value = 'Der Vorgang konnte nicht abgeschlossen werden.'
  errorMessage.value = message
}

function getErrorMessage(error: unknown): string {
  if (error instanceof TypeError) {
    return 'Der Server ist nicht erreichbar. Prüfe die Verbindung und die Server-URL.'
  }

  if (error instanceof Error) {
    return error.message
  }

  return 'Ein unbekannter Fehler ist aufgetreten.'
}
</script>

<template>
  <main class="identity-page">
    <h1>Passonym Identity</h1>

    <p>
      Verifiziere deine Identität mit ZKPassport und registriere dich anschließend auf der
      Plattform.
    </p>

    <section class="status-panel" :class="`status-${status}`" aria-live="polite">
      <p>{{ statusMessage }}</p>

      <p v-if="errorMessage" class="error-message">
        {{ errorMessage }}
      </p>
    </section>

    <div id="zkpassport" />

    <p v-if="status === 'success'" class="success-message">
      Du kannst jetzt zur Plattform zurückkehren.
    </p>
  </main>
</template>

<style scoped>
.identity-page {
  width: min(100% - 2rem, 640px);
  margin: 3rem auto;
  font-family: system-ui, sans-serif;
}

.status-panel {
  margin: 1.5rem 0;
  padding: 1rem;
  border: 1px solid #d1d5db;
  border-radius: 8px;
}

.status-verifying,
.status-registering,
.status-initializing {
  background: #f3f4f6;
}

.status-success {
  border-color: #16a34a;
}

.status-error {
  border-color: #dc2626;
}

.error-message {
  color: #b91c1c;
}

.success-message {
  color: #15803d;
}
</style>
```
